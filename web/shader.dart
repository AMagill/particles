library shader;
import 'dart:web_gl' as webgl;

class Shader {
  webgl.RenderingContext _gl;
  webgl.Program _shaderProgram;
  final Map<String, int> attributes;
  var uniforms = new Map<String, webgl.UniformLocation>();

  Shader(webgl.RenderingContext this._gl, 
      String vertSource, String fragSource,
      Map<String, int> this.attributes) {
    
    // Compile vertex shader
    webgl.Shader vs = _gl.createShader(webgl.RenderingContext.VERTEX_SHADER);
    _gl.shaderSource(vs, vertSource);
    _gl.compileShader(vs);
    if (!_gl.getShaderParameter(vs, webgl.RenderingContext.COMPILE_STATUS)) { 
      String logText = _gl.getShaderInfoLog(vs);
      var ex = new ShaderException(logText, source:vertSource); 
      throw ex;
    }
    
    // Compile fragment shader
    webgl.Shader fs = _gl.createShader(webgl.RenderingContext.FRAGMENT_SHADER);
    _gl.shaderSource(fs, fragSource);
    _gl.compileShader(fs);
    if (!_gl.getShaderParameter(fs, webgl.RenderingContext.COMPILE_STATUS)) { 
      String logText = _gl.getShaderInfoLog(fs);
      var ex = new ShaderException(logText, source:fragSource);
      throw ex;
    }
    
    // Assemble the program
    _shaderProgram = _gl.createProgram();
    _gl.attachShader(_shaderProgram, vs);
    _gl.attachShader(_shaderProgram, fs);

    // Bind attributes as requested
    attributes.forEach((key,val) {
      _gl.bindAttribLocation(_shaderProgram, val, key);
    });

    // Link
    _gl.linkProgram(_shaderProgram);
    _gl.useProgram(_shaderProgram);
    if (!_gl.getProgramParameter(_shaderProgram, webgl.RenderingContext.LINK_STATUS)) { 
      String logText = _gl.getProgramInfoLog(_shaderProgram);
      var ex = new ShaderException(logText);
      throw ex;
    }

    // Get uniform pointers
    num nUniforms = _gl.getProgramParameter(_shaderProgram, webgl.ACTIVE_UNIFORMS);
    for (int i = 0; i < nUniforms; i++) {
      var info = _gl.getActiveUniform(_shaderProgram, i);
      uniforms[info.name] = _gl.getUniformLocation(_shaderProgram, info.name);
    }
  }
  
  webgl.UniformLocation operator[](String name) {
    return uniforms[name];
  }
  
  void use() {
    _gl.useProgram(_shaderProgram);
  }
}

class ShaderException implements Exception {
  String _logText, _message;
  
  ShaderException(this._logText, {source: null}) {
    _message = _logText.trim();

    // If there's source, attempt to show the offending line
    if (source != null) {
      var match = new RegExp("[a-zA-Z]+: [0-9]+:([0-9]+)")
        .firstMatch(_logText);
      if (match != null) {
        var lineno = int.parse(match.group(1));
        var lines = source.split("\n");
        _message += ' : "' + lines[lineno-1] + '"';
      }
    }
  }
  String toString() => _message;
}

