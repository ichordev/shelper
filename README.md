# Shelper

A helper library for loading, reloading, and unloading bgfx shaders.

Depends on [BindBC-bgfx](https://github.com/BindBC/bindbc-bgfx) v1.0.0 or higher.

## API
The library's `shaderPath` variable indicates the location of your shader binaries. By default, it is set to `shaders/`.

Shelper expects shaders to have the following file extensions:
- `*.vert.bin` for vertex shaders.
- `*.frag.bin` for fragment shaders.
- `*.comp.bin` for compute shaders.

### Functions
```d
bgfx.ProgramHandle load(string vert, string frag);
```
Loads two shader files and creates a shader program. `vert` and `frag` should be only be a file name, without a file extension.
Example:
```d
shaderPath = "shaders/";
myProgram = shelper.load(
	"myShader", //will open "shaders/myShader.vert.bin"
	"myShader", //will open "shaders/myShader.frag.bin"
);
```

---

```d
bgfx.ProgramHandle load(string comp);
```
Loads a shader file and creates a compute shader program. `comp` should be only be a file name, without a file extension.

---

```d
void reload(ref bgfx.ProgramHandle program);
```
Reloads `program`'s shader files afresh from the disk and sets `program` to a newly created `bgfx.ProgramHandle`.
> [!NOTE]\
> This function always creates new underlying `bgfx.ShaderHandle`s, and the old ones will only be destroyed if no other Shelper-managed `bgfx.ProgramHandle` is using them. Because of this, it's best to use the version of the function below when reloading more than one shader.

---

```d
void reload(R)(R programs)
if(hasAssignableElements!R && is(ElementType!R == bgfx.ProgramHandle*));
```
Reloads `programs`' shader files afresh from the disk and sets the handles in `programs` to newly created `bgfx.ProgramHandle`s.
Example:
```d
auto myShader1 = shelper.load("myShaderA", "myShaderA");
auto myShader2 = shelper.load("myShaderA", "myShaderB");
auto myShader3 = shelper.load("myShaderC", "myShaderB");
auto myShader4 = shelper.load("myShaderC", "myShaderA");

//sometime later:
shelper.reload([
	&myShader1,
	&myShader2,
	&myShader3,
	&myShader4,
]);
```

---

```d
bool unload(bgfx.ProgramHandle program) nothrow @nogc;
```
Destroys `program`, and cleans up its underlying `bgfx.ShaderHandle`s if there are no other Shelper-managed `bgfx.ProgramHandle`s using them.

---

```d
void unloadAllShaderPrograms() nothrow @nogc;
```
Destroys all `bgfx.ProgramHandle`s managed by Shelper, and cleans up all of their underlying `bgfx.ShaderHandle`s.
