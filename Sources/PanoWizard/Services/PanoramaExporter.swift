import Foundation

struct PanoramaViewpoint: Codable, Equatable, Sendable {
    var yawRadians = 0.0
    var pitchRadians = 0.0
    var verticalFieldOfViewDegrees = 75.0
}

protocol PanoramaExporting: Sendable {
    func exportHTML(
        panoramaURL: URL,
        adjustments: PanoramaAdjustments,
        title: String,
        initialViewpoint: PanoramaViewpoint,
        to destinationURL: URL
    ) async throws
}

struct FilePanoramaExporter: PanoramaExporting {
    func exportHTML(
        panoramaURL: URL,
        adjustments: PanoramaAdjustments,
        title: String,
        initialViewpoint: PanoramaViewpoint,
        to destinationURL: URL
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let panorama = try Data(contentsOf: panoramaURL).base64EncodedString()
            let safeTitle = title
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            let html = Self.html(
                title: safeTitle,
                panoramaBase64: panorama,
                adjustments: adjustments.sanitized,
                initialViewpoint: initialViewpoint
            )
            try html.write(
                to: destinationURL,
                atomically: true,
                encoding: .utf8
            )
        }.value
    }

    private static func html(
        title: String,
        panoramaBase64: String,
        adjustments: PanoramaAdjustments,
        initialViewpoint: PanoramaViewpoint
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
        <script>
        const panoramaSource="data:image/jpeg;base64,\(panoramaBase64)";
        const canvas=document.querySelector("#view"),gl=canvas.getContext("webgl");
        if(!gl)document.body.innerHTML="<p>WebGL is required to view this panorama.</p>";
        const vertex=`attribute vec2 p;varying vec2 n;void main(){n=p;gl_Position=vec4(p,0.,1.);}`;
        const fragment=`precision highp float;varying vec2 n;uniform sampler2D pano;
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
        vec4 c=texture2D(pano,uv);
        gl_FragColor=vec4(adjust(c.rgb,uv),1.);}`;
        function shader(type,source){const s=gl.createShader(type);gl.shaderSource(s,source);
        gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw gl.getShaderInfoLog(s);return s}
        const program=gl.createProgram();gl.attachShader(program,shader(gl.VERTEX_SHADER,vertex));
        gl.attachShader(program,shader(gl.FRAGMENT_SHADER,fragment));gl.linkProgram(program);gl.useProgram(program);
        const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
        gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),gl.STATIC_DRAW);
        const position=gl.getAttribLocation(program,"p");gl.enableVertexAttribArray(position);
        gl.vertexAttribPointer(position,2,gl.FLOAT,false,0,0);
        function texture(unit,source){const tex=gl.createTexture();gl.activeTexture(gl.TEXTURE0+unit);
        gl.bindTexture(gl.TEXTURE_2D,tex);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
        const image=new Image();image.onload=()=>{gl.activeTexture(gl.TEXTURE0+unit);
        gl.bindTexture(gl.TEXTURE_2D,tex);gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,false);
        gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,image);draw()};image.src=source}
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
        const supportsGestureZoom="ongesturestart" in window;
        let y=initialYaw,p=initialPitch,f=initialFOV,last=null,gestureFOV=f,
        wheelZoom=null,wheelZoomTimer=null;
        function resize(){const d=devicePixelRatio||1,w=innerWidth*d,h=innerHeight*d;
        if(canvas.width!==w||canvas.height!==h){canvas.width=w;canvas.height=h;gl.viewport(0,0,w,h)}}
        function draw(){resize();gl.uniform1f(gl.getUniformLocation(program,"yaw"),y);
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
        y-=(e.clientX-last.clientX)*.005;p=Math.max(-PI/2+.001,
        Math.min(PI/2-.001,p-(e.clientY-last.clientY)*.005));last=e;draw()});
        canvas.addEventListener("pointerup",()=>last=null);
        canvas.addEventListener("pointercancel",()=>last=null);
        function endWheelZoom(){wheelZoom=null;if(wheelZoomTimer)clearTimeout(wheelZoomTimer);wheelZoomTimer=null}
        canvas.addEventListener("wheel",e=>{e.preventDefault();const a=eventAnchor(e);
        if(e.ctrlKey){if(supportsGestureZoom)return;endWheelZoom();
        setFOV(f*180/PI*Math.exp(e.deltaY*.01),a[0],a[1]);return}
        if(Math.abs(e.deltaY)>=Math.abs(e.deltaX)){if(!wheelZoom)wheelZoom={a:a,
        fixed:directionAt(a[0],a[1],f)};setFOV(f*180/PI+e.deltaY*.04,wheelZoom.a[0],
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
