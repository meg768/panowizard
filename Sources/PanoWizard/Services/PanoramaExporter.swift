import Foundation

struct PanoramaViewpoint: Codable, Equatable, Sendable {
    var yawRadians = 0.0
    var pitchRadians = 0.0
    var verticalFieldOfViewDegrees = 75.0
}

protocol PanoramaExporting: Sendable {
    func exportHTML(
        panoramaURL: URL,
        nadirOverlayURL: URL?,
        zenithOverlayURL: URL?,
        nadirRetouchURL: URL?,
        zenithRetouchURL: URL?,
        title: String,
        initialViewpoint: PanoramaViewpoint,
        to destinationURL: URL
    ) async throws
}

struct FilePanoramaExporter: PanoramaExporting {
    func exportHTML(
        panoramaURL: URL,
        nadirOverlayURL: URL?,
        zenithOverlayURL: URL?,
        nadirRetouchURL: URL?,
        zenithRetouchURL: URL?,
        title: String,
        initialViewpoint: PanoramaViewpoint,
        to destinationURL: URL
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let panorama = try Data(contentsOf: panoramaURL).base64EncodedString()
            let nadirOverlay = try nadirOverlayURL.map {
                try Data(contentsOf: $0).base64EncodedString()
            }
            let zenithOverlay = try zenithOverlayURL.map {
                try Data(contentsOf: $0).base64EncodedString()
            }
            let nadirRetouch = try nadirRetouchURL.map {
                try Data(contentsOf: $0).base64EncodedString()
            }
            let zenithRetouch = try zenithRetouchURL.map {
                try Data(contentsOf: $0).base64EncodedString()
            }
            let safeTitle = title
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            let html = Self.html(
                title: safeTitle,
                panoramaBase64: panorama,
                nadirOverlayBase64: nadirOverlay,
                zenithOverlayBase64: zenithOverlay,
                nadirRetouchBase64: nadirRetouch,
                zenithRetouchBase64: zenithRetouch,
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
        nadirOverlayBase64: String?,
        zenithOverlayBase64: String?,
        nadirRetouchBase64: String?,
        zenithRetouchBase64: String?,
        initialViewpoint: PanoramaViewpoint
    ) -> String {
        let nadirOverlaySource = nadirOverlayBase64.map {
            "\"data:image/png;base64,\($0)\""
        } ?? "null"
        let zenithOverlaySource = zenithOverlayBase64.map {
            "\"data:image/png;base64,\($0)\""
        } ?? "null"
        let nadirRetouchSource = nadirRetouchBase64.map {
            "\"data:image/png;base64,\($0)\""
        } ?? "null"
        let zenithRetouchSource = zenithRetouchBase64.map {
            "\"data:image/png;base64,\($0)\""
        } ?? "null"
        return """
        <!doctype html>
        <html lang="sv">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <title>\(title)</title>
        <style>
        *{box-sizing:border-box}html,body,canvas{width:100%;height:100%;margin:0}
        body{overflow:hidden;background:#08090b;color:white;font:14px system-ui}
        canvas{display:block;touch-action:none;cursor:grab}canvas:active{cursor:grabbing}
        #hint{position:fixed;left:16px;top:16px;padding:8px 11px;border-radius:10px;
        background:#0008;backdrop-filter:blur(8px);pointer-events:none}
        #zoom{position:fixed;right:16px;bottom:16px;display:flex;gap:8px}
        #zoom button{width:44px;height:44px;border:0;border-radius:22px;background:#0009;
        color:white;font:26px system-ui;cursor:pointer;backdrop-filter:blur(8px)}
        </style>
        </head>
        <body><canvas id="view"></canvas><div id="hint">Dra för att se dig omkring · rulla för att zooma</div>
        <div id="zoom"><button id="out" aria-label="Zooma ut">−</button><button id="in" aria-label="Zooma in">+</button></div>
        <script>
        const panoramaSource="data:image/jpeg;base64,\(panoramaBase64)";
        const nadirOverlaySource=\(nadirOverlaySource);
        const zenithOverlaySource=\(zenithOverlaySource);
        const nadirRetouchSource=\(nadirRetouchSource);
        const zenithRetouchSource=\(zenithRetouchSource);
        const canvas=document.querySelector("#view"),gl=canvas.getContext("webgl");
        if(!gl)document.body.innerHTML="<p>WebGL krävs för att visa panoramat.</p>";
        const vertex=`attribute vec2 p;varying vec2 n;void main(){n=p;gl_Position=vec4(p,0.,1.);}`;
        const fragment=`precision highp float;varying vec2 n;uniform sampler2D pano,nadirRepair,zenithRepair,nadirRetouch,zenithRetouch;
        uniform float yaw,pitch,fov,aspect,hasNadirRepair,hasZenithRepair,hasNadirRetouch,hasZenithRetouch;
        const float PI=3.141592653589793;
        void main(){float t=tan(fov*.5);vec3 d=normalize(vec3(n.x*aspect*t,n.y*t,1.));
        float cp=cos(pitch),sp=sin(pitch);d=vec3(d.x,d.y*cp-d.z*sp,d.y*sp+d.z*cp);
        float cy=cos(yaw),sy=sin(yaw);d=vec3(d.x*cy+d.z*sy,d.y,-d.x*sy+d.z*cy);
        vec2 uv=vec2(fract(.5+atan(d.x,d.z)/(2.*PI)),.5-asin(clamp(d.y,-1.,1.))/PI);
        vec4 c=texture2D(pano,uv);vec3 r=vec3(d.x,-d.z,-d.y);
        if(hasNadirRepair>.5&&r.z>.0001){vec2 q=vec2(.5)+.2886751346*r.xy/r.z;
        vec4 o=texture2D(nadirRepair,q);c.rgb=mix(c.rgb,o.rgb,o.a);}
        vec3 z=vec3(d.x,d.z,d.y);if(hasZenithRepair>.5&&z.z>.0001){
        vec2 q=vec2(.5)+.2886751346*z.xy/z.z;vec4 o=texture2D(zenithRepair,q);
        c.rgb=mix(c.rgb,o.rgb,o.a);}if(hasZenithRetouch>.5&&z.z>.0001){
        vec2 q=vec2(.5)+.5*z.xy/z.z;vec4 o=texture2D(zenithRetouch,q);
        c.rgb=mix(c.rgb,o.rgb,o.a);}if(hasNadirRetouch>.5&&r.z>.0001){
        vec2 q=vec2(.5)+.5*r.xy/r.z;vec4 o=texture2D(nadirRetouch,q);
        c.rgb=mix(c.rgb,o.rgb,o.a);}gl_FragColor=vec4(c.rgb,1.);}`;
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
        texture(0,panoramaSource);if(nadirOverlaySource)texture(1,nadirOverlaySource);
        if(zenithOverlaySource)texture(2,zenithOverlaySource);
        if(nadirRetouchSource)texture(3,nadirRetouchSource);
        if(zenithRetouchSource)texture(4,zenithRetouchSource);
        gl.uniform1i(gl.getUniformLocation(program,"pano"),0);
        gl.uniform1i(gl.getUniformLocation(program,"nadirRepair"),1);
        gl.uniform1i(gl.getUniformLocation(program,"zenithRepair"),2);
        gl.uniform1i(gl.getUniformLocation(program,"nadirRetouch"),3);
        gl.uniform1i(gl.getUniformLocation(program,"zenithRetouch"),4);
        gl.uniform1f(gl.getUniformLocation(program,"hasNadirRepair"),nadirOverlaySource?1:0);
        gl.uniform1f(gl.getUniformLocation(program,"hasZenithRepair"),zenithOverlaySource?1:0);
        gl.uniform1f(gl.getUniformLocation(program,"hasNadirRetouch"),nadirRetouchSource?1:0);
        gl.uniform1f(gl.getUniformLocation(program,"hasZenithRetouch"),zenithRetouchSource?1:0);
        const PI=Math.PI;
        let y=\(initialViewpoint.yawRadians),
        p=\(initialViewpoint.pitchRadians),
        f=\(initialViewpoint.verticalFieldOfViewDegrees)*PI/180,last=null,gestureFOV=f;
        function resize(){const d=devicePixelRatio||1,w=innerWidth*d,h=innerHeight*d;
        if(canvas.width!==w||canvas.height!==h){canvas.width=w;canvas.height=h;gl.viewport(0,0,w,h)}}
        function draw(){resize();gl.uniform1f(gl.getUniformLocation(program,"yaw"),y);
        gl.uniform1f(gl.getUniformLocation(program,"pitch"),p);gl.uniform1f(gl.getUniformLocation(program,"fov"),f);
        gl.uniform1f(gl.getUniformLocation(program,"aspect"),canvas.width/canvas.height);
        gl.drawArrays(gl.TRIANGLES,0,6)}
        function setFOV(degrees){f=Math.max(30,Math.min(105,degrees))*PI/180;draw()}
        canvas.addEventListener("pointerdown",e=>{canvas.setPointerCapture(e.pointerId);last=e});
        canvas.addEventListener("pointermove",e=>{if(!last)return;
        y-=(e.clientX-last.clientX)*.005;p=Math.max(-PI/2+.001,
        Math.min(PI/2-.001,p-(e.clientY-last.clientY)*.005));last=e;draw()});
        canvas.addEventListener("pointerup",()=>last=null);
        canvas.addEventListener("pointercancel",()=>last=null);
        canvas.addEventListener("wheel",e=>{e.preventDefault();
        setFOV(f*180/PI+e.deltaY*.04)},{passive:false});
        canvas.addEventListener("gesturestart",e=>{e.preventDefault();gestureFOV=f},{passive:false});
        canvas.addEventListener("gesturechange",e=>{e.preventDefault();
        setFOV(gestureFOV*180/PI/e.scale)},{passive:false});
        document.querySelector("#in").onclick=()=>setFOV(f*180/PI-10);
        document.querySelector("#out").onclick=()=>setFOV(f*180/PI+10);
        addEventListener("keydown",e=>{if(e.key==="ArrowLeft")y-=.08;
        else if(e.key==="ArrowRight")y+=.08;else if(e.key==="ArrowUp")p=Math.max(-PI/2+.001,p-.08);
        else if(e.key==="ArrowDown")p=Math.min(PI/2-.001,p+.08);
        else if(e.key==="+"||e.key==="=")return setFOV(f*180/PI-10);
        else if(e.key==="-")return setFOV(f*180/PI+10);else return;draw()});
        addEventListener("resize",draw);draw();
        </script></body></html>
        """
    }
}
