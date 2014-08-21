import 'dart:html';
import 'dart:math';
import 'dart:web_gl' as webgl;
import 'package:vector_math/vector_math.dart';
import 'package:vector_math/vector_math_lists.dart';
import 'dart:typed_data';
import 'shader.dart';
import 'frame_buffer.dart';


class ParticleScene {
  static const int _dims = 64;
  static const int _nParticles = _dims * _dims;

  int _width, _height;
  webgl.RenderingContext _gl;
  Shader _posShader, _screenShader, _textureShader;
  webgl.Buffer _vboParticles, _vboQuad;
  List<FrameBuffer> _fboPos;
  bool oddFrame = true;
  
  ParticleScene(CanvasElement canvas) {
    _width  = canvas.width;
    _height = canvas.height;
    _gl     = canvas.getContext("experimental-webgl");
    
    _gl.getExtension('OES_texture_float');
    
    _vboParticles = _gl.createBuffer();
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboParticles);
    //var particles = new Float32List(2 * _nParticles);
    //var partPos   = new Vector2List.view(particles, 0, 2);
    var partPos = new Vector2List(_nParticles);
    for (var i = 0; i < partPos.length; i++) {
      var x = i % _dims;
      var y = (i-x)/_dims;
      partPos[i] = new Vector2(x + 0.5, y + 0.5) / _dims.toDouble();
    }
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, partPos.buffer, webgl.STATIC_DRAW);
    
    _vboQuad = _gl.createBuffer();
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboQuad);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, 
        new Float32List.fromList([ 0.0, 0.0,  1.0, 0.0,
                                   0.0, 1.0,  1.0, 1.0]), webgl.STATIC_DRAW);

    _fboPos = [new FrameBuffer(_gl, _dims, _dims),
               new FrameBuffer(_gl, _dims, _dims)];
    
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
    _gl.uniform1i(_posShader['uPosTex'], 0);

    _screenShader.use();
    _gl.uniform1i(_screenShader['uPosTex'], 0);
    _gl.uniformMatrix4fv(_screenShader['uProjection'], false, mProjection.storage);  
  }
  
  void _initShaders() {
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

void main() {
  //gl_FragColor = vec4(vUV, 0.0, 1.0);
  gl_FragColor = texture2D(uPosTex, vUV);
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

void main() {
  gl_Position = uProjection * vec4(texture2D(uPosTex, aPosition).rgb, 1.0);
  vPosition = aPosition;
  gl_PointSize = 1.0;
}
    """;
    
    String fsScreen = """
precision mediump int;
precision mediump float;

varying vec2  vPosition;

uniform sampler2D uPosTex;

void main() {
  gl_FragColor = vec4(0.0, 1.0, 0.0, 1.0);
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
  }
  
  void render() {
    
    _gl.bindFramebuffer(webgl.FRAMEBUFFER, _fboPos[oddFrame?1:0].fbo);
    _gl.viewport(0, 0, _dims, _dims);
    _gl.clearColor(0.0, 0, 0, 1);
    _gl.activeTexture(webgl.TEXTURE0);
    _gl.bindTexture(webgl.TEXTURE_2D, _fboPos[oddFrame?0:1].imageTex);
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboQuad);
    _gl.vertexAttribPointer(0, 2, webgl.FLOAT, false, 0, 0);
    _gl.enableVertexAttribArray(0);
    _posShader.use();
    _gl.clear(webgl.COLOR_BUFFER_BIT);
    _gl.drawArrays(webgl.TRIANGLE_STRIP, 0, 4);
    
    
    _gl.bindFramebuffer(webgl.FRAMEBUFFER, null);
    _gl.viewport(0, 0, _width, _height);
    _gl.clearColor(0, 0, 0, 1);
    _gl.activeTexture(webgl.TEXTURE0);
    _gl.bindTexture(webgl.TEXTURE_2D, _fboPos[oddFrame?1:0].imageTex);
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboParticles);
    _gl.vertexAttribPointer(0, 2, webgl.FLOAT, false, 0, 0);
    _gl.enableVertexAttribArray(0);
    _screenShader.use();
    _gl.clear(webgl.COLOR_BUFFER_BIT);
    _gl.drawArrays(webgl.POINTS, 0, _nParticles);

    /*
    _gl.activeTexture(webgl.TEXTURE0);
    _gl.bindTexture(webgl.TEXTURE_2D, _fboPos[0].imageTex);
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboQuad);
    _gl.vertexAttribPointer(0, 2, webgl.FLOAT, false, 0, 0);
    _gl.enableVertexAttribArray(0);
    _textureShader.use();
    _gl.clear(webgl.COLOR_BUFFER_BIT);
    _gl.drawArrays(webgl.TRIANGLE_STRIP, 0, 4);
*/
    
    oddFrame = !oddFrame;
  }
}



var scene;
void main() {
  var canvas = document.querySelector("#glCanvas");
  scene = new ParticleScene(canvas);
  
  window.animationFrame
    ..then((time) => animate(time));
}

void animate(double time) {
  scene.render();
  
  window.animationFrame
    ..then((time) => animate(time));
  
}
