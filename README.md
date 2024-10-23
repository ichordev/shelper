# Shelper

*Shader helper*&mdash;a helper library for loading, re-loading, and un-loading bgfx shaders.

Depends on [BindBC-bgfx](https://github.com/BindBC/bindbc-bgfx) v1.0.0 or higher.

## Setup
First, you'll need an instance of the `Shelper` struct template.
```d
import shelper;

Shelper!() myShaders;
```
> [!NOTE]\
> Mutable `Shelper` instances should only be passed around by reference.

You can set the `path` property to tell Shelper the location of your shader binaries.
It defaults to the relative path `shaders/`.
```
myShaders.path = "assets/shaders"; //same as "./assets/shaders/"
```

Shelper requires your shader binaries to have the `.bin` file extension.

By default, Shelper also uses glslang-style naming-conventions to differentiate different shader types:
- `*.vert.bin` for vertex shaders.
- `*.frag.bin` for fragment shaders.
- `*.comp.bin` for compute shaders.

These can be re-configured when instantiating the `Shelper` struct template:
```d
Shelper!("%s.vert",  "%s.frag",  "%s.comp") myShaders3; //the default
Shelper!("%s.vsh",   "%s.fsh",   "%s.csh")  myShaders1; //a popular alternative
Shelper!("vs_%s",    "fs_%s",    "cs_%s")   myShaders2; //the format of bgfx's examples
```

## Loading
Once everything is set up to your liking, use `load` to open your shaders and create a shader program:
```d
auto myShaderProgram = myShaders.load(
	"myShader", //will open "shaders/myShader.vert.bin"
	"myShader", //will open "shaders/myShader.frag.bin"
);
```

Supply only one name to create a compute shader:
```d
auto myComputeShader = myShaders.load(
	"myShader", //will open "shaders/myShader.comp.bin"
);
```

## Re-Loading
When you need to reload a single shader program, pass its program handle into the `reload` function:
```d
myShaders.reload(myShaderProgram);
```
This reloads `myShaderProgram`'s shaders afresh from the disk and sets `myShaderProgram` to a newly-created `bgfx.ProgramHandle`.

> [!NOTE]\
> This function always creates new underlying `bgfx.ShaderHandle`s, but the old ones will only be destroyed if no other `bgfx.ProgramHandle` in the same Shelper instance is using them.
> Because of this, it's best to use the version of the function below when reloading more than one shader.

When you need to reload more than one shader program, pass an array of `bgfx.ShaderHandle` pointers into `reload`:
```d
auto myShaderProg1 = myShaders.load("myShaderA", "myShaderA");
auto myShaderProg2 = myShaders.load("myShaderA", "myShaderB");
auto myShaderProg3 = myShaders.load("myShaderC", "myShaderB");
auto myShaderProg4 = myShaders.load("myShaderC", "myShaderA");

myShaders.reload([&myShaderProg1, &myShaderProg2, &myShaderProg3, &myShaderProg4]);
```
It reloads the shaders of each passed shader program afresh from the disk, and sets each handle to a newly-created program handle.

## Un-Loading
When you're done with a certain shader program, you can use `unload` on it:
```d
myShaders.unload(myShaderProgram);
```
This destroys `myShaderProgram`, but only cleans up its underlying `bgfx.ShaderHandle`s if there are no other `bgfx.ProgramHandle`s in the same Shelper instance using them.

When you're about to shut down your program, run `unloadAll`:
```d
myShaders.unloadAll();
```
This will destroy all `bgfx.ProgramHandle`s managed by that Shelper instance, and clean up all of their underlying `bgfx.ShaderHandle`s.

## Documentation

Further documentation is available in the source code of this library.
