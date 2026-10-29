import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PanoramaViewpoint: Codable, Equatable, Sendable {
    var yawRadians = 0.0
    var pitchRadians = 0.0
    var verticalFieldOfViewDegrees = 75.0
}

enum HTMLPanoramaSize: String, CaseIterable, Sendable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case original = "Original"

    var maximumWidth: Int {
        switch self {
        case .small: 4_096
        case .medium: 8_192
        case .large: 12_288
        case .original: 0
        }
    }
}

protocol PanoramaExporting: Sendable {
    func exportHTML(
        panoramaURL: URL,
        adjustments: PanoramaAdjustments,
        title: String,
        initialViewpoint: PanoramaViewpoint,
        size: HTMLPanoramaSize,
        jpegQuality: Double,
        to destinationURL: URL
    ) async throws
}

enum HTMLNavigationPreferences {
    static let invertDragDirection = "PanoWizard.HTML.invertDragDirection"
    static let invertScrollZoom = "PanoWizard.HTML.invertScrollZoom"
}

struct FilePanoramaExporter: PanoramaExporting {
    func exportHTML(
        panoramaURL: URL,
        adjustments: PanoramaAdjustments,
        title: String,
        initialViewpoint: PanoramaViewpoint,
        size: HTMLPanoramaSize = .medium,
        jpegQuality: Double = 0.82,
        to destinationURL: URL
    ) async throws {
        let dragDirection = UserDefaults.standard.bool(
            forKey: HTMLNavigationPreferences.invertDragDirection
        ) ? -1 : 1
        let scrollDirection = UserDefaults.standard.bool(
            forKey: HTMLNavigationPreferences.invertScrollZoom
        ) ? -1 : 1
        try await Task.detached(priority: .userInitiated) {
            let data = try Self.jpegData(from: panoramaURL, size: size, quality: jpegQuality)
            // Separate small data elements avoid one enormous HTML script token.
            // Decode into a Blob instead of a full-resolution data URL.
            let chunkSize = 49_152
            let panorama = stride(from: 0, to: data.count, by: chunkSize).map { offset in
                let end = min(offset + chunkSize, data.count)
                return "<script type=\"application/octet-stream\" class=\"panorama-chunk\">"
                    + data.subdata(in: offset..<end).base64EncodedString() + "</script>"
            }.joined(separator: "\n")
            let safeTitle = title
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            let html = Self.html(
                title: safeTitle,
                panoramaChunks: panorama,
                adjustments: adjustments.sanitized,
                initialViewpoint: initialViewpoint,
                dragDirection: dragDirection,
                scrollDirection: scrollDirection
            )
            try html.write(
                to: destinationURL,
                atomically: true,
                encoding: .utf8
            )
        }.value
    }

    private static func jpegData(
        from sourceURL: URL,
        size: HTMLPanoramaSize,
        quality: Double
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let sourceWidth = properties[kCGImagePropertyPixelWidth] as? Int
        else { throw CocoaError(.fileReadCorruptFile) }
        let image: CGImage?
        if size == .original {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        } else {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: min(size.maximumWidth, sourceWidth),
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary)
        }
        let data = NSMutableData()
        guard let image,
              let destination = CGImageDestinationCreateWithData(
                data, UTType.jpeg.identifier as CFString, 1, nil
              ) else { throw CocoaError(.fileReadCorruptFile) }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }

    private static func html(
        title: String,
        panoramaChunks: String,
        adjustments: PanoramaAdjustments,
        initialViewpoint: PanoramaViewpoint,
        dragDirection: Int,
        scrollDirection: Int
    ) -> String {
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <title>\(title)</title>
        <style>
        *{box-sizing:border-box}html,body,canvas{width:100%;height:100%;margin:0}
        body{overflow:hidden;background:#08090b;color:white;font:14px system-ui}
        canvas{display:block;touch-action:none;cursor:grab}canvas:active{cursor:grabbing}
        </style>
        </head>
        <body><canvas id="view"></canvas>
        \(panoramaChunks)
        <script>
        const panoramaChunks=[...document.querySelectorAll(".panorama-chunk")];
        const panoramaSource=URL.createObjectURL(new Blob(panoramaChunks.map(chunk=>{
        const decoded=atob(chunk.textContent),bytes=new Uint8Array(decoded.length);chunk.textContent="";chunk.remove();
        for(let i=0;i<decoded.length;i++)bytes[i]=decoded.charCodeAt(i);return bytes}),{type:"image/jpeg"}));
        const canvas=document.querySelector("#view"),gl=canvas.getContext("webgl2");
        function showError(message){document.body.textContent=message}
        if(!gl){showError("WebGL 2 is required to view this panorama.");throw new Error("WebGL 2 unavailable")}
        let panoramaLoaded=false;
        const vertex=`#version 300 es
        in vec2 p;out vec2 n;void main(){n=p;gl_Position=vec4(p,0.,1.);}`;
        const fragment=`#version 300 es
        precision highp float;precision highp sampler2DArray;
        in vec2 n;out vec4 fragmentColor;uniform sampler2DArray pano;
        uniform vec2 panoramaSize;uniform float tileSide,tileStride,tileColumns;
        vec4 samplePanorama(vec2 uv){
        vec2 pixel=clamp(uv*panoramaSize,vec2(0.),panoramaSize);
        vec2 tile=min(floor(pixel/tileStride),ceil(panoramaSize/tileStride)-vec2(1.));
        vec2 local=(pixel-tile*tileStride+vec2(1.))/tileSide;
        return texture(pano,vec3(local,tile.y*tileColumns+tile.x));}
        uniform float yaw,pitch,fov,aspect;
        uniform float exposure,brightness,contrast,highlights,shadows,whites,blacks,temperature,tint,vibrance,saturation;
        const float PI=3.141592653589793;
        vec3 toLinear(vec3 c){vec3 lo=c/12.92;vec3 hi=pow((c+.055)/1.055,vec3(2.4));return mix(lo,hi,step(vec3(.04045),c));}
        vec3 toSRGB(vec3 c){vec3 lo=c*12.92;vec3 hi=1.055*pow(c,vec3(1./2.4))-.055;return mix(lo,hi,step(vec3(.0031308),c));}
        vec3 adjust(vec3 encoded,vec2 uv){vec3 c=toLinear(clamp(encoded,0.,1.));
        c*=exp2(exposure);c+=brightness*.0025;float l=dot(c,vec3(.2126,.7152,.0722));
        c+=shadows*.0035*pow(clamp(1.-l,0.,1.),2.);c+=highlights*.0035*pow(clamp(l,0.,1.),2.);
        float wm=smoothstep(.55,1.,l),bm=1.-smoothstep(0.,.45,l);c*=1.+whites*.0035*wm;c+=blacks*.002*bm;
        c=(c-.18)*exp2(contrast/100.)+.18;c=clamp(c,0.,1.);float te=temperature/100.,ti=tint/100.;
        c.r+=te*(1.-c.r)*.12;c.b-=te*(1.-c.b)*.12;c.r+=ti*(1.-c.r)*.04;c.g-=ti*(1.-c.g)*.08;c.b+=ti*(1.-c.b)*.04;
        l=dot(c,vec3(.2126,.7152,.0722));float ch=max(c.r,max(c.g,c.b))-min(c.r,min(c.g,c.b));
        c=mix(vec3(l),c,1.+vibrance/100.*(1.-clamp(ch,0.,1.)));l=dot(c,vec3(.2126,.7152,.0722));
        c=mix(vec3(l),c,1.+saturation/100.);return toSRGB(clamp(c,0.,1.));}
        void main(){float t=tan(fov*.5);vec3 d=normalize(vec3(n.x*aspect*t,n.y*t,1.));
        float cp=cos(pitch),sp=sin(pitch);d=vec3(d.x,d.y*cp-d.z*sp,d.y*sp+d.z*cp);
        float cy=cos(yaw),sy=sin(yaw);d=vec3(d.x*cy+d.z*sy,d.y,-d.x*sy+d.z*cy);
        vec2 uv=vec2(fract(.5+atan(d.x,d.z)/(2.*PI)),.5-asin(clamp(d.y,-1.,1.))/PI);
        vec4 c=samplePanorama(uv);
        fragmentColor=vec4(adjust(c.rgb,uv),1.);}`;
        function shader(type,source){const s=gl.createShader(type);gl.shaderSource(s,source);
        gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw gl.getShaderInfoLog(s);return s}
        const program=gl.createProgram();gl.attachShader(program,shader(gl.VERTEX_SHADER,vertex));
        gl.attachShader(program,shader(gl.FRAGMENT_SHADER,fragment));gl.linkProgram(program);gl.useProgram(program);
        const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
        gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),gl.STATIC_DRAW);
        const position=gl.getAttribLocation(program,"p");gl.enableVertexAttribArray(position);
        gl.vertexAttribPointer(position,2,gl.FLOAT,false,0,0);
        function texture(unit,source){
        const tex=gl.createTexture();gl.activeTexture(gl.TEXTURE0+unit);
        gl.bindTexture(gl.TEXTURE_2D_ARRAY,tex);
        gl.texParameteri(gl.TEXTURE_2D_ARRAY,gl.TEXTURE_MIN_FILTER,gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D_ARRAY,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D_ARRAY,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D_ARRAY,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
        const image=new Image();image.onerror=()=>{URL.revokeObjectURL(source);showError("The panorama image could not be read.")};
        image.onload=()=>{try{
        const maximum=gl.getParameter(gl.MAX_TEXTURE_SIZE),layers=gl.getParameter(gl.MAX_ARRAY_TEXTURE_LAYERS);
        let side=Math.min(2048,maximum),stride=side-2;
        while(Math.ceil(image.width/stride)*Math.ceil(image.height/stride)>layers&&side<maximum){
        side=Math.min(side*2,maximum);stride=side-2}
        const columns=Math.ceil(image.width/stride),rows=Math.ceil(image.height/stride);
        if(columns*rows>layers)throw new Error("This device cannot display all panorama tiles.");
        gl.activeTexture(gl.TEXTURE0+unit);gl.bindTexture(gl.TEXTURE_2D_ARRAY,tex);
        gl.texStorage3D(gl.TEXTURE_2D_ARRAY,1,gl.RGBA8,side,side,columns*rows);
        const tile=document.createElement("canvas");tile.width=side;tile.height=side;
        const context=tile.getContext("2d");context.imageSmoothingEnabled=false;
        gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,false);
        for(let row=0;row<rows;row++)for(let column=0;column<columns;column++){
        context.clearRect(0,0,side,side);
        const left=column*stride,top=row*stride,sx=Math.max(0,left-1),sy=Math.max(0,top-1);
        const sw=Math.min(image.width-sx,side-(sx-left+1)),sh=Math.min(image.height-sy,side-(sy-top+1));
        context.drawImage(image,sx,sy,sw,sh,sx-left+1,sy-top+1,sw,sh);
        if(column===0)context.drawImage(image,image.width-1,sy,1,sh,0,sy-top+1,1,sh);
        if(left+stride>=image.width)context.drawImage(image,0,sy,1,sh,1+image.width-left,sy-top+1,1,sh);
        if(row===0)context.drawImage(tile,0,1,side,1,0,0,side,1);
        if(top+stride>=image.height){const edge=1+image.height-top;
        context.drawImage(tile,0,edge-1,side,1,0,edge,side,1)}
        gl.texSubImage3D(gl.TEXTURE_2D_ARRAY,0,0,0,row*columns+column,side,side,1,gl.RGBA,gl.UNSIGNED_BYTE,tile);
        if(gl.getError()!==gl.NO_ERROR)throw new Error("The device could not load the panorama textures.");
        }
        gl.uniform2f(gl.getUniformLocation(program,"panoramaSize"),image.width,image.height);
        gl.uniform1f(gl.getUniformLocation(program,"tileSide"),side);
        gl.uniform1f(gl.getUniformLocation(program,"tileStride"),stride);
        gl.uniform1f(gl.getUniformLocation(program,"tileColumns"),columns);
        panoramaLoaded=true;draw();
        }catch(error){showError(error.message)}finally{URL.revokeObjectURL(source)}};image.src=source}
        texture(0,panoramaSource);
        gl.uniform1i(gl.getUniformLocation(program,"pano"),0);
        gl.uniform1f(gl.getUniformLocation(program,"exposure"),\(adjustments.exposure));
        gl.uniform1f(gl.getUniformLocation(program,"brightness"),\(adjustments.brightness));
        gl.uniform1f(gl.getUniformLocation(program,"contrast"),\(adjustments.contrast));
        gl.uniform1f(gl.getUniformLocation(program,"highlights"),\(adjustments.highlights));
        gl.uniform1f(gl.getUniformLocation(program,"shadows"),\(adjustments.shadows));
        gl.uniform1f(gl.getUniformLocation(program,"whites"),\(adjustments.whites));
        gl.uniform1f(gl.getUniformLocation(program,"blacks"),\(adjustments.blacks));
        gl.uniform1f(gl.getUniformLocation(program,"temperature"),\(adjustments.temperature));
        gl.uniform1f(gl.getUniformLocation(program,"tint"),\(adjustments.tint));
        gl.uniform1f(gl.getUniformLocation(program,"vibrance"),\(adjustments.vibrance));
        gl.uniform1f(gl.getUniformLocation(program,"saturation"),\(adjustments.saturation));
        const PI=Math.PI,initialYaw=\(initialViewpoint.yawRadians),
        initialPitch=\(initialViewpoint.pitchRadians),
        initialFOV=\(initialViewpoint.verticalFieldOfViewDegrees)*PI/180;
        const dragDirection=\(dragDirection),scrollDirection=\(scrollDirection);
        const supportsGestureZoom="ongesturestart" in window;
        let y=initialYaw,p=initialPitch,f=initialFOV,last=null,gestureFOV=f,
        wheelZoom=null,wheelZoomTimer=null;
        function resize(){const d=devicePixelRatio||1,w=innerWidth*d,h=innerHeight*d;
        if(canvas.width!==w||canvas.height!==h){canvas.width=w;canvas.height=h;gl.viewport(0,0,w,h)}}
        function draw(){resize();if(!panoramaLoaded)return;gl.uniform1f(gl.getUniformLocation(program,"yaw"),y);
        gl.uniform1f(gl.getUniformLocation(program,"pitch"),p);gl.uniform1f(gl.getUniformLocation(program,"fov"),f);
        gl.uniform1f(gl.getUniformLocation(program,"aspect"),canvas.width/canvas.height);
        gl.drawArrays(gl.TRIANGLES,0,6)}
        function norm(v){const l=Math.hypot(v[0],v[1],v[2])||1;return[v[0]/l,v[1]/l,v[2]/l]}
        function directionAt(ax,ay,field){const t=Math.tan(field*.5),a=canvas.width/canvas.height;
        let d=norm([(ax*2-1)*a*t,(1-ay*2)*t,1]),cp=Math.cos(p),sp=Math.sin(p);
        d=[d[0],d[1]*cp-d[2]*sp,d[1]*sp+d[2]*cp];const cy=Math.cos(y),sy=Math.sin(y);
        return[d[0]*cy+d[2]*sy,d[1],-d[0]*sy+d[2]*cy]}
        function wrapAngle(a){return Math.atan2(Math.sin(a),Math.cos(a))}
        function setFOV(degrees){
        const target=Math.max(30,Math.min(105,degrees))*PI/180;if(Math.abs(target-f)<1e-9)return;
        f=target;draw()}
        function eventAnchor(e){const r=canvas.getBoundingClientRect();return[
        Math.max(0,Math.min(1,(e.clientX-r.left)/Math.max(r.width,1))),
        Math.max(0,Math.min(1,(e.clientY-r.top)/Math.max(r.height,1)))]}
        canvas.addEventListener("pointerdown",e=>{canvas.setPointerCapture(e.pointerId);last=e});
        canvas.addEventListener("pointermove",e=>{if(!last)return;
        y-=(e.clientX-last.clientX)*.005*dragDirection;p=Math.max(-PI/2+.001,
        Math.min(PI/2-.001,p-(e.clientY-last.clientY)*.005*dragDirection));last=e;draw()});
        canvas.addEventListener("pointerup",()=>last=null);
        canvas.addEventListener("pointercancel",()=>last=null);
        function endWheelZoom(){wheelZoom=null;if(wheelZoomTimer)clearTimeout(wheelZoomTimer);wheelZoomTimer=null}
        canvas.addEventListener("wheel",e=>{e.preventDefault();const a=eventAnchor(e);
        if(e.ctrlKey){if(supportsGestureZoom)return;endWheelZoom();
        setFOV(f*180/PI*Math.exp(e.deltaY*.01),a[0],a[1]);return}
        const scrollDelta=Math.abs(e.deltaY)>=Math.abs(e.deltaX)?e.deltaY:e.deltaX;
        if(Math.abs(scrollDelta)>.01){if(!wheelZoom)wheelZoom={a:a,
        fixed:directionAt(a[0],a[1],f)};setFOV(f*180/PI+scrollDelta*.04*scrollDirection,wheelZoom.a[0],
        wheelZoom.a[1],wheelZoom.fixed);if(wheelZoomTimer)clearTimeout(wheelZoomTimer);
        wheelZoomTimer=setTimeout(endWheelZoom,120)}
        },{passive:false});
        canvas.addEventListener("gesturestart",e=>{e.preventDefault();gestureFOV=f},{passive:false});
        canvas.addEventListener("gesturechange",e=>{e.preventDefault();
        const a=eventAnchor(e);setFOV(gestureFOV*180/PI/e.scale,a[0],a[1])},{passive:false});
        addEventListener("keydown",e=>{if(e.metaKey&&(e.key==="+"||e.key==="=")){
        e.preventDefault();return setFOV(f*180/PI-10)}else if(e.metaKey&&e.key==="-"){
        e.preventDefault();return setFOV(f*180/PI+10)}else if(e.metaKey&&e.key==="0"){
        e.preventDefault();y=initialYaw;p=initialPitch;f=initialFOV;return draw()}
        if(e.key==="ArrowLeft")y-=.08;
        else if(e.key==="ArrowRight")y+=.08;else if(e.key==="ArrowUp")p=Math.max(-PI/2+.001,p-.08);
        else if(e.key==="ArrowDown")p=Math.min(PI/2-.001,p+.08);
        else return;draw()});
        addEventListener("resize",draw);draw();
        </script></body></html>
        """
    }
}
