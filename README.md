qUINT
========================================================

qUINT is a shader framework for ReShade 3, written in its proprietary ReShade FX language. It aims to deliver effects to cover most of ReShade's common use cases in a small and easy package. Notable properties:

* Next-gen effects abstracted behind intuitive controls
* Highly polished code for best quality and performance, taking care of many artifacts similar implementations suffer from
* Full use of ReShade FX so it can serve as a reference implementation of everything RSFX has to offer
* Fully compatible to the official ReShade shader repository
* Modular setup for faster compile times if only a part of qUINT is required

Prerequisites
------------------------

- Latest ReShade version to ensure maximum compatibility
- Completed ReShade tutorial

Setup
------------------------

- `Optional` if you don't use the default ReShade shader package or put them to a different location, add `.\Shaders` to the EffectSearchPaths of the ReShade .ini file (same name as the ReShade dll, d3d9.ini - d3d11.ini, dxgi.ini, opengl32.ini are possible names) and create the respective folder.

- Put the content of the qUINT `Shaders` folder into the `Shaders` folder present in your ReShade installation location. The file and folder structure should look like this:

	- [file] ReShade DLL (d3d9.dll/d3d10.dll/d3d11.dll/dxgi.dll/opengl32.dll)
	- [file] ReShade INI (d3d9.ini/d3d10.ini/d3d11.ini/dxgi.ini/opengl32.ini)
	- [folder] Shaders 
		- [file] qUINT files

- Open the `Shaders` folder you just put the files in and delete any `.fx` (not `.fxh`!) file you don't need, so in case you don't require the bloom shader, delete `qUINT_bloom.fx`.

Contents
------------------------

* `MXAO` is a Screen-Space Ambient Occlusion algorithm that can serve as a replacement for existing SSAO implementations in video games or to polish dated games that lack such a feature. Algorithmically similar to latest-gen tech like ASSAO and HBAO+, although it features some relatively unique features such as indirect illumination, smoothing filter for depth-derived normal maps, double-layer option at no additional cost and others. Highly configurable, easily tweakable.

* `ADOF` This is a Depth of Field shader that aspires to give movie-quality bokeh blur to video games. It provides a very high quality DoF effect with artistic controls, ideal for both screenshots and gameplay. The bokeh discs it produces can be polygonal, circular and anything in between, it also features a disc occlusion feature (where the bokeh discs look like boolean intersection between 2 circles) and chromatic aberration at bokeh shape edges. This is done by a unique gradient-based algorithm that has a very low constant cost ignorant of scene complexity or blur settings. 
To prohibit focused areas from bleeding their color into blurred areas - a common visual error found in many DoF filters - the shader employs a highly sophisticated solution that is capable of migitating this artifact completely without the overhead of common solutions that also mostly underperform.

* `Lightroom` is a highly comprehensive set of color grading filters, modeled after industry applications such as Adobe Lightroom, Da Vinci Resolve and others. It allows for miniscule adjustments of the scene colors with the ability to embed the current preset into a 3D LUT - a small image file that contains all color grading that the LUT.fx of the ReShade repository can easily load and apply. This both saves performance as reading a LUT is faster and it also protects your work as you only need to deploy the LUT along with your preset so you can keep your configuration private.

* `Bloom` is a filter that adds a glow around bright screen areas, adapting to the current scene brightness. Most current games already contain such an effect but most older implementations are very simple. The shader runs as fast as 0.1ms / frame and due to a smart down- and upscale system it has a very small memory footprint.

* `Screen-Space Reflections` adds reflections to the scene, using the data that is already available in the image. This is the spiritual successor of the "Reflective Bumpmapping" (RBM) in older ReShade shaders. It creates much more accurate reflections while not being quite as hard on performance. 
As a Screen-Space technique, it suffers like all similar implementation from the fact that nothing outside the screen can be reflected. It also cannot distinguish between reflective and non-reflective surfaces, so it will just cover everything with a reflection layer. This restricts its usability to screenshots and certain games but where it is useful, it can completely transform the look of the scene.

### CC BY-NC-ND 3.0 licensed.
