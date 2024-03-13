module shelper;

import core.time;
import std.exception, std.format, std.range.primitives, std.typecons;
import bindbc.bgfx;

class ShelperException: Exception{
	this(string msg, string file=__FILE__, size_t line=__LINE__){
		super(msg, file, line);
	}
}

string shaderPath = "shaders/";

struct ShaderData{
	const bgfx.ShaderHandle handle = bgfx.invalidHandle!ShaderHandle;
	const ShaderKey key;
	size_t refCount = 1;
}

struct ShaderKey{
	string name;
	MonoTime timestamp;
}

private{
	ShaderData*[ShaderKey] allLoadedShaders;
	ShaderData*[string] recentLoadedShaders;
	
	bgfx.ShaderHandle loadShader(string filePath){
		import std.file;
		enforce(filePath.exists, new ShelperException(format("Shader file '%s' not found", filePath)));
		enforce(filePath.isFile, new ShelperException(format("Attempted to load shader from '%s', but it's not a file", filePath)));
		
		const memory = bgfx.copy(cast(void*)filePath.read(), cast(uint)filePath.getSize());
		
		auto shader = bgfx.createShader(memory);
		enforce(shader != bgfx.invalidHandle!ShaderHandle, new ShelperException(format("Shader '%s' did not load properly.", filePath)));
		return shader;
	}
	
	bgfx.ShaderHandle getNewShader(string name, out ShaderKey key, ShaderData*[string] recent){
		const handle = loadShader(shaderPath ~ name ~ ".bin");
		key = ShaderKey(name, MonoTime.currTime);
		auto data = new ShaderData(handle, key);
		allLoadedShaders[key] = data;
		recent[name] = data;
		return handle;
	}
	
	bgfx.ShaderHandle getShader(string name, out ShaderKey key, ShaderData*[string] recent){
		if(auto oldShader = name in recent){
			(*oldShader).refCount++;
			key = (*oldShader).key;
			return (*oldShader).handle;
		}
		
		return getNewShader(name, key, recent);
	}
	
	void unloadShader(ShaderKey key) nothrow @nogc{
		if(auto data = key in allLoadedShaders){
			if(--(*data).refCount <= 0){
				bgfx.destroy((*data).handle);
				allLoadedShaders.remove(key);
				
				if(auto recentData = key.name in recentLoadedShaders){
					if(*recentData is *data){
						recentLoadedShaders.remove(key.name);
					}
				}
			}
		}
	}
	
	bgfx.ShaderHandle reloadShader(ref ShaderKey key){
		unloadShader(key);
		return getNewShader(key.name, key, recentLoadedShaders);
	}
	
	bgfx.ShaderHandle[] reloadShaders(R)(ref R[] keys)
	if(hasAssignableElements!R && is(ElementType!R == ShaderKey)){
		foreach(key; keys){
			unloadShader(key);
		}
		auto ret = new bgfx.ShaderHandle[](keys.length);
		foreach(i, ref key; keys){
			ret[i] = getNewShader(key.name, key, recentLoadedShaders);
		}
		return ret;
	}
}

struct ProgramData{
	ShaderKey vert, frag, comp;
}

ProgramData[bgfx.ProgramHandle] shaderPrograms;

bgfx.ProgramHandle load(string vert, string frag){
	ProgramData data;
	auto handle = bgfx.createProgram(
		getShader(vert~".vert", data.vert, recentLoadedShaders),
		getShader(frag~".frag", data.frag, recentLoadedShaders),
		false,
	);
	enforce(handle != invalidHandle!ProgramHandle, new ShelperException(format("Failed to create program with vert shader '%s', and frag shader '%s'.", data.vert, data.frag)));
	shaderPrograms[handle] = data;
	return handle;
}

bgfx.ProgramHandle load(string comp){
	ProgramData data;
	auto handle = bgfx.createProgram(
		getShader(comp~".comp", data.comp, recentLoadedShaders),
		false,
	);
	enforce(handle != invalidHandle!ProgramHandle, new ShelperException(format("Failed to create program with shader '%s'.", data.comp)));
	shaderPrograms[handle] = data;
	return handle;
}

void reload(ref bgfx.ProgramHandle program){
	if(auto data = program in shaderPrograms){
		bgfx.destroy(program);
		
		bgfx.ProgramHandle newHandle;
		
		if(data.comp.name is null){
			newHandle = bgfx.createProgram(
				reloadShader(data.vert),
				reloadShader(data.frag),
				false,
			);
			enforce(newHandle != invalidHandle!ProgramHandle, new ShelperException(format("Failed to re-create program with vert shader '%s', and frag shader '%s'.", data.vert, data.frag)));
		}else{
			newHandle = bgfx.createProgram(
				reloadShader(data.comp),
				false,
			);
			enforce(newHandle != invalidHandle!ProgramHandle, new ShelperException(format("Failed to re-create program with shader '%s'.", data.comp)));
		}
		
		shaderPrograms.remove(program);
		program = newHandle;
		shaderPrograms[program] = *data;
	}else{
		program = bgfx.invalidHandle!ProgramHandle;
	}
}

void reload(R)(R programs)
if(hasAssignableElements!R && is(ElementType!R == bgfx.ProgramHandle*)){
	auto oldData = new Nullable!(ProgramData)[](programs.length);
	
	//unload all old shaders at once, so that we'll only create one set of new ones
	foreach(i, ref program; programs){
		if(auto data = *program in shaderPrograms){
			oldData[i] = *data;
			bgfx.destroy(*program);
			if(data.comp.name is null){
				unloadShader(data.vert);
				unloadShader(data.frag);
			}else{
				unloadShader(data.comp);
			}
			shaderPrograms.remove(*program);
		}
	}
	
	//load the new shaders & programs
	ShaderData*[string] mostRecentShaders;
	foreach(i, nData; oldData){
		if(!nData.isNull){
			auto data = nData.get();
			bgfx.ProgramHandle newHandle;
			if(data.comp.name is null){
				newHandle = bgfx.createProgram(
					getShader(data.vert.name, data.vert, mostRecentShaders),
					getShader(data.frag.name, data.frag, mostRecentShaders),
					false,
				);
			}else{
				newHandle = bgfx.createProgram(
					getShader(data.comp.name, data.comp, mostRecentShaders),
					false,
				);
			}
			shaderPrograms[newHandle] = data;
			*programs[i] = newHandle;
		}else{
			*programs[i] = bgfx.invalidHandle!ProgramHandle;
		}
	}
	
	//merge our new shaders into `recentLoadedShaders`
	foreach(key, val; mostRecentShaders){
		recentLoadedShaders[key] = val;
	}
}

bool unload(bgfx.ProgramHandle program) nothrow @nogc{
	if(auto data = program in shaderPrograms){
		bgfx.destroy(program);
		unloadShader(data.vert);
		unloadShader(data.frag);
		return true;
	}
	return false;
}

void unloadAllShaderPrograms() nothrow @nogc{
	foreach(program; shaderPrograms.byKey()){
		unload(program);
	}
	shaderPrograms = null;
	assert(allLoadedShaders.length == 0);
	assert(recentLoadedShaders.length == 0);
}
