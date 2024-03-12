module shelper;

import std.exception, std.format;
import bindbc.bgfx;

class ShelperException: Exception{
	this(string msg, string file=__FILE__, size_t line=__LINE__){
		super(msg, file, line);
	}
}

string shaderPath = "shaders/";

private{
	struct ShaderData{
		bgfx.ShaderHandle handle;
		size_t refCount = 1;
	}
	
	ShaderData[string] loadedShaders;
	
	bgfx.ShaderHandle loadShader(string filePath){
		import std.file;
		enforce(filePath.exists, new ShelperException(format("Shader file '%s' not found", filePath)));
		enforce(filePath.isFile, new ShelperException(format("Attempted to load shader from '%s', but it's not a file", filePath)));
		
		const memory = bgfx.copy(cast(void*)filePath.read(), cast(uint)filePath.getSize());
		
		auto shader = bgfx.createShader(memory);
		enforce(shader != bgfx.invalidHandle!ShaderHandle, new ShelperException(format("Shader '%s' did not load properly.", filePath)));
		return shader;
	}
	
	bgfx.ShaderHandle getShader(string name){
		if(auto oldShader = name in loadedShaders){
			oldShader.refCount++;
			return oldShader.handle;
		}
		
		auto handle = loadShader(shaderPath ~ name ~ ".bin");
		loadedShaders[name] = ShaderData(handle);
		return handle;
	}
	
	void unloadShader(string name) nothrow @nogc{
		if(auto data = name in loadedShaders){
			if(--data.refCount <= 0){
				bgfx.destroy(data.handle);
				loadedShaders.remove(name);
			}
		}
	}
	
	bgfx.ShaderHandle reloadShader(string name){
		unloadShader(name);
		return getShader(name);
	}
}

struct ProgramData{
	string vertShaderName, fragShaderName, compShaderName;
	
	this(string vert, string frag) nothrow pure @safe{
		vertShaderName = vert~".vert";
		fragShaderName = frag~".frag";
	}
	
	this(string comp) nothrow pure @safe{
		compShaderName = comp~".comp";
	}
}

ProgramData[bgfx.ProgramHandle] shaderPrograms;

bgfx.ProgramHandle load(string vert, string frag){
	auto data = ProgramData(vert, frag);
	auto handle = bgfx.createProgram(
		getShader(data.vertShaderName),
		getShader(data.fragShaderName),
		false,
	);
	enforce(handle != invalidHandle!ProgramHandle, new ShelperException(format("Failed to create program with shaders '%s' and '%s'.", data.vertShaderName, data.fragShaderName)));
	shaderPrograms[handle] = data;
	return handle;
}

bgfx.ProgramHandle load(string comp){
	auto data = ProgramData(comp);
	auto handle = bgfx.createProgram(
		getShader(data.compShaderName),
		bgfx.invalidHandle!ShaderHandle,
		false,
	);
	enforce(handle != invalidHandle!ProgramHandle, new ShelperException(format("Failed to create program with shader '%s'.", data.compShaderName)));
	shaderPrograms[handle] = data;
	return handle;
}

bgfx.ProgramHandle reload(bgfx.ProgramHandle program){
	if(auto data = program in shaderPrograms){
		bgfx.destroy(program);
		
		bgfx.ProgramHandle newHandle;
		
		if(data.compShaderName is null){
			newHandle = bgfx.createProgram(
				reloadShader(data.vertShaderName),
				reloadShader(data.fragShaderName),
				false,
			);
		}else{
			newHandle = bgfx.createProgram(
				reloadShader(data.compShaderName),
				bgfx.invalidHandle!ShaderHandle,
				false,
			);
		}
		
		shaderPrograms.remove(program);
		shaderPrograms[newHandle] = *data;
		
		return newHandle;
	}
	return bgfx.invalidHandle!ProgramHandle;
}

bool unload(bgfx.ProgramHandle program) nothrow @nogc{
	if(auto data = program in shaderPrograms){
		bgfx.destroy(program);
		unloadShader(data.vertShaderName);
		unloadShader(data.fragShaderName);
		return true;
	}
	return false;
}

void unloadAllShaderPrograms() nothrow @nogc{
	foreach(program; shaderPrograms.byKey()){
		unload(program);
	}
	shaderPrograms = null;
	assert(loadedShaders.length == 0);
}
