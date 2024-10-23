/+
+               Copyright 2024 Aya Partridge
+ Distributed under the Boost Software License, Version 1.0.
+     (See accompanying file LICENSE_1_0.txt or copy at
+           http://www.boost.org/LICENSE_1_0.txt)
+/
module shelper;

import core.time;
import std.format, std.path, std.range, std.traits, std.typecons;
import bindbc.bgfx;

///All Shelper exceptions extend this class.
class ShelperException: Exception{
	this(string msg, string file=__FILE__, size_t line=__LINE__) nothrow pure @safe{
		super(msg, file, line);
	}
}
///Thrown when trying to load a shader file that is too large.
class ShelperTooLongException: ShelperException{
	this(string filePath, ulong fileSize, string file=__FILE__, size_t line=__LINE__) pure @safe{
		super(format!"Shader file '%s' is too long (%s bytes), must be at most %s bytes."(filePath, fileSize, uint.max), file, line);
	}
}
///Thrown when bgfx can't create a shader/program with the relevant input.
class ShelperCreationException: ShelperException{
	this(string msg, string file=__FILE__, size_t line=__LINE__) nothrow pure @safe{
		super(msg, file, line);
	}
}

/**
Loads a non-managed shader.

Should only be used when you don't want Shelper's convenient unloading/reloading functionality.

Throws:
	- `ShelperTooLongException` if the file size won't fit in a `uint`.
	- `ShelperCreationException` if bgfx fails to create the shader.
*/
bgfx.ShaderHandle loadShader(string filePath){
	import std.file: getSize;
	const fileSize = filePath.getSize();
	if(fileSize >= uint.max) throw new ShelperTooLongException(filePath, fileSize);
	
	auto memory = cast(bgfx.Memory*)bgfx.alloc(cast(uint)fileSize);
	{
		import std.stdio;
		auto file = File(filePath.array, "rb");
		const readResult = file.rawRead(memory.data[0..fileSize]);
		assert(readResult.length == memory.size);
	}
	
	auto shader = bgfx.createShader(memory);
	if(shader == bgfx.invalidHandle!ShaderHandle) throw new ShelperCreationException(format!"bgfx failed to create a shader from file '%s'."(filePath));
	return shader;
}

///Internal storage used to keep track of a shader handle.
struct ShaderData{
	bgfx.ShaderHandle handle = bgfx.invalidHandle!ShaderHandle;
	ShaderKey key;
	size_t refCount = 1;
}

///A key used to look up a shader handle.
struct ShaderKey{
	string name;
	MonoTime timestamp;
}

///Internal storage used to keep track of a shader program's underlying shaders.
struct ProgramData{
	bool isCompute = false;
	union{
		struct{
			ShaderKey vert, frag;
		}
		struct{
			ShaderKey comp;
		}
	}
}

struct Shelper(string vertFmt="%s.vert", string fragFmt="%s.frag", string compFmt="%s.comp"){
	static assert(vertFmt != fragFmt && fragFmt != compFmt && vertFmt != compFmt, "The same format must not be used for two different types of shader");
	
	private{
		ShaderData[ShaderKey] allLoadedShaders;
		ShaderData*[string] recentLoadedShaders;
		
		ProgramData[bgfx.ProgramHandle] shaderPrograms;
		
		string _path = "shaders/";
		string _pathAbs = null;
	}
	
	///A relative or absolute file path to your shader binaries.
	@property path() nothrow @nogc pure @safe => _path;
	///ditto
	@property path(string val) nothrow @nogc pure @safe{
		_pathAbs = null;
		_path = val;
	}
	
	///An absolute file path to your shader binaries.
	@property pathAbs() @safe{
		if(_pathAbs) return _pathAbs;
		
		_pathAbs = asAbsolutePath(_path).array;
		return _pathAbs;
	}
	
	///How many shaders this instance is using.
	@property length() nothrow @nogc pure @safe => allLoadedShaders.length;
	
	private{
		///Unconditionally load a shader from the disk
		bgfx.ShaderHandle getNewShader(string name, out ShaderKey key, ShaderData*[string] recent){
			const handle = loadShader(buildPath(pathAbs, name~".bin"));
			key = ShaderKey(name, MonoTime.currTime);
			allLoadedShaders[key] = ShaderData(handle, key);
			recent[name] = key in allLoadedShaders;
			return handle;
		}
		
		///Load a shader from the disk, unless it has already been loaded
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
				if(--data.refCount <= 0){
					bgfx.destroy(data.handle);
					allLoadedShaders.remove(key);
					
					if(auto recentData = key.name in recentLoadedShaders){
						if(*recentData is data){
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
		
		void reloadShaders(R)(ref R[] keys)
		if(hasAssignableElements!R && is(ElementType!R == ShaderKey)){
			foreach(key; keys){
				unloadShader(key);
			}
			foreach(i, ref key; keys){
				getNewShader(key.name, key, recentLoadedShaders);
			}
			return ret;
		}
	}
	
	/**
	Create a shader program with vertex & fragment shader.
	
	If either of the underlying shaders are already loaded, then they will be
	re-used rather than being freshly loaded from the disk.
	
	Params:
		vertName = The filename of the vertex shader file, without its file extension.
		fragName = The filename of the fragment shader file, without its file extension.
	Returns: A newly created shader program handle.
	
	Throws: `ShelperCreationException` if bgfx fails to create the new shader(s) or shader program.
	*/
	bgfx.ProgramHandle load(string vertName, string fragName){
		auto data = ProgramData(isCompute: false);
		auto handle = bgfx.createProgram(
			getShader(format!vertFmt(vertName), data.vert, recentLoadedShaders),
			getShader(format!fragFmt(fragName), data.frag, recentLoadedShaders),
			false,
		);
		if(handle == invalidHandle!ProgramHandle) throw new ShelperCreationException(format!"bgfx failed to create a program with vertex shader '%s' and fragment shader '%s'."(data.vert, data.frag));
		shaderPrograms[handle] = data;
		return handle;
	}
	
	/**
	Create a shader program with vertex & fragment shader.
	
	If the underlying shader is already loaded, then it will be
	re-used rather than being freshly loaded from the disk.
	
	Params:
		compName = The filename of the compute shader file, without its file extension.
	Returns: A newly created shader program handle.
	
	Throws: `ShelperCreationException` if bgfx fails to create a new shader or the shader program.
	*/
	bgfx.ProgramHandle load(string compName){
		auto data = ProgramData(isCompute: true);
		auto handle = bgfx.createProgram(
			getShader(format!compFmt(compName), data.comp, recentLoadedShaders),
			false,
		);
		if(handle == invalidHandle!ProgramHandle) throw new ShelperCreationException(format!"bgfx failed to create a program with compute shader '%s'."(data.comp));
		shaderPrograms[handle] = data;
		return handle;
	}
	
	/**
	Reloads `program`'s shaders from the disk, and sets `program` to a newly-created program handle.
	
	If `program` was not originally loaded with this `Shelper` instance, it is set to `bgfx.invalidHandle!ProgramHandle`.
	
	Note:
		This function always creates new underlying `bgfx.ShaderHandle`(s), but the old one(s) will only be destroyed if
		no other `bgfx.ProgramHandle` in this `Shelper` instance is using them.
		Because of this, it's best to use the the multi-reload overload when reloading more than one shader program.
	
	Throws: `ShelperCreationException` if bgfx fails to create the new shader(s) or shader program.
	*/
	void reload(ref bgfx.ProgramHandle program){
		if(auto data = program in shaderPrograms){
			bgfx.destroy(program);
			
			bgfx.ProgramHandle newHandle;
			
			if(!data.isCompute){
				newHandle = bgfx.createProgram(
					reloadShader(data.vert),
					reloadShader(data.frag),
					false,
				);
				if(newHandle == invalidHandle!ProgramHandle) throw new ShelperCreationException(format!"bgfx failed to re-create a program with vertex shader '%s' and fragment shader '%s'."(data.vert, data.frag));
			}else{
				newHandle = bgfx.createProgram(
					reloadShader(data.comp),
					false,
				);
				if(newHandle == invalidHandle!ProgramHandle) throw new ShelperCreationException(format!"bgfx failed to re-create program with compute shader '%s'."(data.comp));
			}
			
			shaderPrograms.remove(program);
			program = newHandle;
			shaderPrograms[program] = *data;
		}else{
			program = bgfx.invalidHandle!ProgramHandle;
		}
	}
	
	/**
	Reloads each shader program pointed to in `programs` from the disk.
	
	If a program was not originally loaded with this `Shelper` instance, it is set to `bgfx.invalidHandle!ProgramHandle`.
	
	Throws: `ShelperCreationException` if bgfx fails to create the new shaders or shader programs.
	*/
	void reload(R)(R programs)
	if(hasAssignableElements!R && is(ElementType!R == bgfx.ProgramHandle*)){
		auto oldData = new Nullable!(ProgramData)[](programs.length);
		
		//unload all old shaders at once, so that we'll only create one set of new ones
		foreach(i, ref program; programs){
			if(auto data = *program in shaderPrograms){
				oldData[i] = *data;
				bgfx.destroy(*program);
				if(!data.isCompute){
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
				if(!data.isCompute){
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
	
	/**
	Destroys `program`.
	
	Note:
		Only cleans up the underlying `bgfx.ShaderHandle`(s) if there are no other
		`bgfx.ProgramHandle`s in the same Shelper instance using them.
	
	Returns: `true` unless `program` doesn't exist or doesn't belong to this `Shelper` instance.
	*/
	bool unload(bgfx.ProgramHandle program) nothrow @nogc{
		if(auto data = program in shaderPrograms){
			bgfx.destroy(program);
			unloadShader(data.vert);
			unloadShader(data.frag);
			return true;
		}
		return false;
	}
	
	///Destroys all shader programs from this `Shelper` instance, and cleans up all of its underlying `bgfx.ShaderHandle`s.
	void unloadAll() nothrow @nogc
	out(; allLoadedShaders.length == 0)
	out(; recentLoadedShaders.length == 0){
		foreach(program; shaderPrograms.byKey()){
			unload(program);
		}
		shaderPrograms = null;
	}
}
