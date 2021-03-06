import 'dart:html';
import 'dart:web_gl' as webgl;
import 'package:vector_math/vector_math.dart';
import 'package:vector_math/vector_math_lists.dart';
import 'dart:typed_data';
import 'shader.dart';
import 'frame_buffer.dart';


class ParticleScene {
  static const int _noiseDims = 256;
  int _dims;
  int _nParticles;
  double _particleBrightness, _particleSize;

  int _width, _height;
  webgl.RenderingContext _gl;
  Shader _posShader, _screenShader, _textureShader, _noiseShader;
  webgl.Buffer _vboParticles, _vboQuad;
  List<FrameBuffer> _fboPos;
  FrameBuffer _fboNoise;
  bool oddFrame = false;
  String _viewMode = "particles";
  
  
  String get viewMode => _viewMode;
  void   set viewMode(String mode) {
    _viewMode = mode;
    //render();
  }
  
  int  get mapDims => _dims;
  void set mapDims(int dims) {
    _dims = dims;
    _nParticles = dims * dims;
    
    if (dims <= 256) {
      _particleBrightness = 0.5;
      _particleSize = 5.0;
    } else if (dims <= 512) {
      _particleBrightness = 0.03;
      _particleSize = 4.0;      
    } else if (dims <= 1024) {
      _particleBrightness = 0.005;
      _particleSize = 4.0;      
    } else if (dims <= 2048) {
      _particleBrightness = 0.005;
      _particleSize = 2.0;      
    } else {
      _particleBrightness = 0.005;
      _particleSize = 1.0;            
    }
    
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboParticles);
    var partPos = new Vector2List(_nParticles);
    for (var i = 0; i < partPos.length; i++) {
      var x = i % _dims;
      var y = (i-x)/_dims;
      partPos[i] = new Vector2(x + 0.5, y + 0.5) / _dims.toDouble();
    }
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, partPos.buffer, webgl.STATIC_DRAW);
  }
  
  ParticleScene(CanvasElement canvas) {
    _width  = canvas.width;
    _height = canvas.height;
    _gl     = canvas.getContext("experimental-webgl");
    
    _gl.getExtension('OES_texture_float');
    _gl.getExtension('OES_texture_float_linear');
    
    _gl.enable(webgl.BLEND);
        
    _vboParticles = _gl.createBuffer();
    mapDims = 512;
    
    _vboQuad = _gl.createBuffer();
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboQuad);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, 
        new Float32List.fromList([ 0.0, 0.0,  1.0, 0.0,
                                   0.0, 1.0,  1.0, 1.0]), webgl.STATIC_DRAW);

    _fboPos = [new FrameBuffer(_gl, _dims, _dims, type: webgl.FLOAT),
               new FrameBuffer(_gl, _dims, _dims, type: webgl.FLOAT)];

    _gl.activeTexture(webgl.TEXTURE2);
    _fboNoise = new FrameBuffer(_gl, _noiseDims, _noiseDims, 
        type: webgl.FLOAT, filtering: webgl.LINEAR);
    
    _gl.activeTexture(webgl.TEXTURE0);
    _gl.bindTexture(webgl.TEXTURE_2D, _fboPos[0].imageTex);
    var initialPos = new Vector3List(_nParticles);
    for (var i = 0; i < _nParticles; i++) {
      var x = (  i % _dims       + 0.5) / _dims;
      var y = (((i / _dims) - x) + 0.5) / _dims;
      initialPos[i] = new Vector3(x*2-1, y*2-1, 0.0);
    }
    _gl.texImage2DTyped(webgl.TEXTURE_2D, 0, webgl.RGB, _dims, _dims, 0,
        webgl.RGB, webgl.FLOAT, initialPos.buffer);
    
    
/*    _gl.activeTexture(webgl.TEXTURE1);
    _gl.texParameteri(webgl.TEXTURE_2D, webgl.TEXTURE_MIN_FILTER, webgl.NEAREST);
    _gl.texParameteri(webgl.TEXTURE_2D, webgl.TEXTURE_MAG_FILTER, webgl.NEAREST);
*/
    
    _initShaders();
    
    var mProjection = makeOrthographicMatrix(-1, 1, -1, 1, -1, 1);

    
    _posShader.use();
    _gl.uniform1i(_posShader['uPosTex'],   0);
    _gl.uniform1i(_posShader['uNoiseTex'], 2);

    _screenShader.use();
    _gl.uniform1i(_screenShader['uPosTex'], 0);
    _gl.uniformMatrix4fv(_screenShader['uProjection'], false, mProjection.storage);
  }
  
  void _initShaders() {
    String simplexGLSL = """
vec3 mod289(vec3 x)
{
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 mod289(vec4 x)
{
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 permute(vec4 x)
{
  return mod289(((x*34.0)+1.0)*x);
}

vec4 taylorInvSqrt(vec4 r)
{
  return 1.79284291400159 - 0.85373472095314 * r;
}

vec3 fade(vec3 t) {
  return t*t*t*(t*(t*6.0-15.0)+10.0);
}

float cnoise(vec3 P)
{
  vec3 Pi0 = floor(P); // Integer part for indexing
  vec3 Pi1 = Pi0 + vec3(1.0); // Integer part + 1
  Pi0 = mod289(Pi0);
  Pi1 = mod289(Pi1);
  vec3 Pf0 = fract(P); // Fractional part for interpolation
  vec3 Pf1 = Pf0 - vec3(1.0); // Fractional part - 1.0
  vec4 ix = vec4(Pi0.x, Pi1.x, Pi0.x, Pi1.x);
  vec4 iy = vec4(Pi0.yy, Pi1.yy);
  vec4 iz0 = Pi0.zzzz;
  vec4 iz1 = Pi1.zzzz;

  vec4 ixy = permute(permute(ix) + iy);
  vec4 ixy0 = permute(ixy + iz0);
  vec4 ixy1 = permute(ixy + iz1);

  vec4 gx0 = ixy0 * (1.0 / 7.0);
  vec4 gy0 = fract(floor(gx0) * (1.0 / 7.0)) - 0.5;
  gx0 = fract(gx0);
  vec4 gz0 = vec4(0.5) - abs(gx0) - abs(gy0);
  vec4 sz0 = step(gz0, vec4(0.0));
  gx0 -= sz0 * (step(0.0, gx0) - 0.5);
  gy0 -= sz0 * (step(0.0, gy0) - 0.5);

  vec4 gx1 = ixy1 * (1.0 / 7.0);
  vec4 gy1 = fract(floor(gx1) * (1.0 / 7.0)) - 0.5;
  gx1 = fract(gx1);
  vec4 gz1 = vec4(0.5) - abs(gx1) - abs(gy1);
  vec4 sz1 = step(gz1, vec4(0.0));
  gx1 -= sz1 * (step(0.0, gx1) - 0.5);
  gy1 -= sz1 * (step(0.0, gy1) - 0.5);

  vec3 g000 = vec3(gx0.x,gy0.x,gz0.x);
  vec3 g100 = vec3(gx0.y,gy0.y,gz0.y);
  vec3 g010 = vec3(gx0.z,gy0.z,gz0.z);
  vec3 g110 = vec3(gx0.w,gy0.w,gz0.w);
  vec3 g001 = vec3(gx1.x,gy1.x,gz1.x);
  vec3 g101 = vec3(gx1.y,gy1.y,gz1.y);
  vec3 g011 = vec3(gx1.z,gy1.z,gz1.z);
  vec3 g111 = vec3(gx1.w,gy1.w,gz1.w);

  vec4 norm0 = taylorInvSqrt(vec4(dot(g000, g000), dot(g010, g010), dot(g100, g100), dot(g110, g110)));
  g000 *= norm0.x;
  g010 *= norm0.y;
  g100 *= norm0.z;
  g110 *= norm0.w;
  vec4 norm1 = taylorInvSqrt(vec4(dot(g001, g001), dot(g011, g011), dot(g101, g101), dot(g111, g111)));
  g001 *= norm1.x;
  g011 *= norm1.y;
  g101 *= norm1.z;
  g111 *= norm1.w;

  float n000 = dot(g000, Pf0);
  float n100 = dot(g100, vec3(Pf1.x, Pf0.yz));
  float n010 = dot(g010, vec3(Pf0.x, Pf1.y, Pf0.z));
  float n110 = dot(g110, vec3(Pf1.xy, Pf0.z));
  float n001 = dot(g001, vec3(Pf0.xy, Pf1.z));
  float n101 = dot(g101, vec3(Pf1.x, Pf0.y, Pf1.z));
  float n011 = dot(g011, vec3(Pf0.x, Pf1.yz));
  float n111 = dot(g111, Pf1);

  vec3 fade_xyz = fade(Pf0);
  vec4 n_z = mix(vec4(n000, n100, n010, n110), vec4(n001, n101, n011, n111), fade_xyz.z);
  vec2 n_yz = mix(n_z.xy, n_z.zw, fade_xyz.y);
  float n_xyz = mix(n_yz.x, n_yz.y, fade_xyz.x); 
  return 2.2 * n_xyz;
}
""";
    
    String vsPos = """
precision mediump int;
precision mediump float;

attribute vec2  aPosition;

varying vec2 vUV;

void main() {
  gl_Position = vec4(aPosition*2.0-vec2(1.0), 0.0, 1.0);
  vUV = aPosition;
}
    """;
    
    String fsPos = """
precision mediump int;
precision mediump float;

varying vec2 vUV;

uniform sampler2D uPosTex;
uniform sampler2D uNoiseTex;
uniform float uTime, uNoiseScale;

void main() {
  vec3 noise = vec3(texture2D(uNoiseTex, vUV).rgb);
  vec3 pos = texture2D(uPosTex, vUV).rgb;

  //pos += noise;
  pos = noise;

  gl_FragColor = vec4(pos, 1.0);
}
    """;
    
    _posShader = new Shader(_gl, vsPos, fsPos, {'aPosition': 0});

    
    String vsScreen = """
precision mediump int;
precision mediump float;

attribute vec2  aPosition;

varying vec2  vPosition;

uniform mat4      uProjection;
uniform sampler2D uPosTex;
uniform float     uSize;

void main() {
  vec3 pos = texture2D(uPosTex, aPosition).rgb;

  //vec3 pos = vec3(aPosition, 0.0) * 2.0 - 1.0;

  gl_Position = uProjection * vec4(pos, 1.0);
  vPosition = aPosition;
  gl_PointSize = uSize;
}
    """;
    
    String fsScreen = """
precision mediump int;
precision mediump float;

varying vec2  vPosition;

uniform sampler2D uPosTex;
uniform float     uBrightness;

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main() {
  vec3 color = vec3(0.005);
  color = hsv2rgb(vec3(vPosition.rg, 0.5));
  //color = texture2D(uPosTex, vPosition).rgb * 0.5 + vec3(0.5);
  //color = vBlarg * 0.5 + 0.5;
  //color = texture2D(uPosTex, vPosition).rgb * 0.5 + 0.5;
  gl_FragColor = vec4(color * uBrightness, 1.0);
}
    """;
    
    _screenShader = new Shader(_gl, vsScreen, fsScreen, {'aPosition': 0});

    String vsTexture = """
precision mediump int;
precision mediump float;

attribute vec2  aPosition;

varying vec2 vUV;

void main() {
  gl_Position = vec4(aPosition*2.0-vec2(1.0), 0.0, 1.0);
  vUV = aPosition;
}
    """;
    
    String fsTexture = """
precision mediump int;
precision mediump float;

varying vec2 vUV;

uniform sampler2D uPosTex;

void main() {
  gl_FragColor = vec4(texture2D(uPosTex, vUV).rgb * 0.5 + 0.5, 1.0);
}
    """;
    
    _textureShader = new Shader(_gl, vsTexture, fsTexture, {'aPosition': 0});
    
    String fsNoise = """
precision mediump int;
precision mediump float;

varying vec2 vUV;

uniform float uTime;
uniform float uScale;

$simplexGLSL

void main() {
  vec3 color;   //  Offsets to uZ arbitrarily chosen
  color.r = cnoise(vec3(vUV, uTime + 123.4) * uScale);
  color.g = cnoise(vec3(vUV, uTime + 567.8) * uScale);
  color.b = cnoise(vec3(vUV, uTime + 901.2) * uScale);
  gl_FragColor = vec4(color, 1.0);
}
    """;
    
    _noiseShader = new Shader(_gl, vsTexture, fsNoise, {'aPosition': 0});
  }
  
  void render([double time = 0.0]) {
    oddFrame = !oddFrame;
    
    // Generate noise
    _gl.bindFramebuffer(webgl.FRAMEBUFFER, _fboNoise.fbo);
    _gl.viewport(0, 0, _noiseDims, _noiseDims);
    _noiseShader.use();
    _gl.uniform1f(_noiseShader["uTime"], time / 50000.0);
    _gl.uniform1f(_noiseShader["uScale"], 10.0);
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboQuad);
    _gl.vertexAttribPointer(0, 2, webgl.FLOAT, false, 0, 0);
    _gl.enableVertexAttribArray(0);
    _gl.drawArrays(webgl.TRIANGLE_STRIP, 0, 4);
/*
    // Set up for sims
    _gl.viewport(0, 0, _dims, _dims);
    _gl.activeTexture(webgl.TEXTURE0);
    _gl.bindTexture(webgl.TEXTURE_2D, _fboPos[oddFrame?0:1].imageTex);
    _gl.activeTexture(webgl.TEXTURE2);
    _gl.bindTexture(webgl.TEXTURE_2D, _fboNoise.imageTex);
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboQuad);
    _gl.vertexAttribPointer(0, 2, webgl.FLOAT, false, 0, 0);
    _gl.enableVertexAttribArray(0);
    
    // Do velocity sim
    
    // Do position sim
    _gl.bindFramebuffer(webgl.FRAMEBUFFER, _fboPos[oddFrame?1:0].fbo);
    _posShader.use();
    _gl.uniform1f(_posShader["uTime"], time / 50000.0);
    _gl.uniform1f(_posShader["uNoiseScale"], 10.0);
    _gl.clear(webgl.COLOR_BUFFER_BIT);
    _gl.drawArrays(webgl.TRIANGLE_STRIP, 0, 4);
*/
    // Back to normal
    _gl.bindFramebuffer(webgl.FRAMEBUFFER, null);
    _gl.viewport(0, 0, _width, _height);
 
    if (_viewMode == "particles") {
      _gl.blendFunc(webgl.ONE, webgl.ONE);
      _gl.clearColor(0.0, 0.0, 0.0, 1.0);
      _gl.activeTexture(webgl.TEXTURE0);
      //_gl.bindTexture(webgl.TEXTURE_2D, _fboPos[oddFrame?1:0].imageTex);
      _gl.bindTexture(webgl.TEXTURE_2D, _fboNoise.imageTex);
      _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboParticles);
      _gl.vertexAttribPointer(0, 2, webgl.FLOAT, false, 0, 0);
      _gl.enableVertexAttribArray(0);
      _screenShader.use();
      _gl.uniform1f(_screenShader["uBrightness"], _particleBrightness);
      _gl.uniform1f(_screenShader["uSize"], _particleSize);
      _gl.clear(webgl.COLOR_BUFFER_BIT);
      _gl.drawArrays(webgl.POINTS, 0, _nParticles);
      _gl.blendFunc(webgl.ONE, webgl.ZERO);
    }
    
    void setupTexShader(var texture) {
      _gl.activeTexture(webgl.TEXTURE0);
      _gl.bindTexture(webgl.TEXTURE_2D, texture);
      _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboQuad);
      _gl.vertexAttribPointer(0, 2, webgl.FLOAT, false, 0, 0);
      _gl.enableVertexAttribArray(0);
      _textureShader.use();
      _gl.clear(webgl.COLOR_BUFFER_BIT);
      _gl.drawArrays(webgl.TRIANGLE_STRIP, 0, 4);      
    }
    
    if (_viewMode == "posMap") {
      setupTexShader(_fboPos[oddFrame?1:0].imageTex);
    }
    
    if (_viewMode == "noiseMap") {
      setupTexShader(_fboNoise.imageTex);
    }
    
  }
}



var scene;
void main() {
  var canvas = document.querySelector("#glCanvas");
  scene = new ParticleScene(canvas);
  
  var viewModeCombo = document.querySelector("#viewMode") as SelectElement;
  viewModeCombo.onChange.listen((e) => scene.viewMode = viewModeCombo.value);

  var nParticlesCombo = document.querySelector("#nParticles") as SelectElement;
  nParticlesCombo.onChange.listen((e) => scene.mapDims = int.parse(nParticlesCombo.value));

  
  window.animationFrame
    ..then((time) => animate(time));
}

void animate(double time) {
  scene.render(time);
  
  window.animationFrame
    ..then((time) => animate(time));
  
}
