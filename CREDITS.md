# Credits

## AI & Development Tools
- **Development Collaboration**: Development work on this project was shared across **Antigravity** and **Codex**.
- **Antigravity**: Contributed substantial coding and iteration using a combination of **Claude** and **Gemini** AI models.
- **Codex**: Contributed implementation, cleanup, packaging, testing, documentation, and open-source release preparation.
- **Design**: The application icon was created and generated using **Recraft**.

## Python Ecosystem
The backend CLI (ProArchive Converter) relies heavily on the following open-source Python packages to parse, process, and combine `.procreate` data:

- [**Pillow**](https://python-pillow.org): Image manipulation, scaling, compositing, and rendering of flat formats (PNG, JPG).
- [**numpy**](https://numpy.org): High-performance array operations, especially for alpha channel un-premultiplication.
- [**pytoshop**](https://github.com/mdboom/pytoshop): Assembly and encoding of layered Photoshop (`.psd`) files.
- [**python-lzo**](https://github.com/jd-boyd/python-lzo): Python bindings for decompressing the LZO-compressed tile data present inside Procreate chunks.
- [**six**](https://pypi.org/project/six/): Python 2 and 3 compatibility library (a dependency for `pytoshop`).
- [**PyInstaller**](https://pyinstaller.org/): Used to freeze and bundle the Python conversion scripts into a standalone backend executable.

## System Libraries
- [**FFmpeg**](https://ffmpeg.org): Used for stitching together raw `.mp4` video segments from the archive into unified timelapse videos.
- [**LZO**](http://www.oberhumer.com/opensource/lzo/): The core, high-speed LZO data compression library utilized by `python-lzo`.

## Frontend & Apple Technologies
- **SwiftUI**: Apple's native declarative UI framework used for building the interface, split views, and macOS native interactions.
- **Foundation**: Apple's framework utilized for executing the bundled background Python process, async task management, and file coordination.
