# FabDBFEdEnh

A DBF database manager / editor for Windows, written in [X#](https://www.xsharp.eu/).

Open, browse, edit, filter, index and repair xBase tables (**Visual FoxPro, FoxPro/CDX and Clipper/NTX**),
with a fast live grid, a record form view, an index manager, structure editing that keeps your data,
and a JSON export that makes the content of a DBF easy to read for other tools.

![FabDBFEdEnh](FabDBFEdEnh.png)

## Features

### Opening files
- Drivers **DBFVFP**, **DBFCDX** and **DBFNTX**; memo files (FPT / DBT) and structural indexes (CDX) are opened with the table
- Per file: **shared / exclusive**, **read only**, record number column, deleted column
- Several tables at once (MDI), recent files list, a file can be passed on the command line (double click on a `.dbf`);
  a second start hands the file over to the running instance

### Browsing and editing
- **Live grid** working directly on the work area (virtual mode: only the visible records are read, so large tables stay fast)
- Edit cells in place, **append**, **delete / recall** (single record or all), **undo** of the last change, **commit**
- Record locking in shared mode, optional auto commit
- Typed input for character, numeric, integer, date, DateTime, logical, currency, double and float fields
- **Form view** (one record, all fields) and table view, choose the visible fields
- Go to record number, **seek** in the active index, **filter** expression, **scope** on the active order, show / hide deleted records
- **DBClipboard**: copy records (also additive) and paste them over a record or append them

### Memo and binary data
- Memo fields open in a text editor (ICSharpCode.TextEditor), trailing padding is handled for you
- **Binary memo** (`M:B`) and **binary character** (`C:B`) fields open in a **hex viewer**, as does the **hex view of the current record**
- **FPT analysis**: block types, dead space, overlapping or broken memo pointers

### Indexes
- **Index manager**: create, edit and delete orders, take the orders of another DBF, rebuild the whole production CDX
- Open index files, select the active order, **ReIndex**

### Structure
- **Create** a new DBF (field types depend on the driver) and generate an X# record model class for it
- **Modify structure**: add, change, reorder and delete fields. Data is converted, field names can be changed,
  AutoIncrement values and field flags are kept, indexes are listed for recreation, and the original is kept as a dated backup
- Structure info of the open table (header, fields, indexes)

### Utilities
- **DBReplace** (value or expression, optional condition), **Pack**, **Zap**, **ReIndex**, record count
- **Export JSON**: the whole table, or just the current view, as an indented array of objects
  (`Deleted`, `RecNo`, then every field)

### Options
- Default driver, locking, default path, date format and century / epoch (the VO date settings), display font
- Settings are stored in `%APPDATA%\FabDBFEdEnh\FabDBFEdEnh.ini`; unhandled errors are logged to `%APPDATA%\FabDBFEdEnh\Error.log`

### Keyboard
| | | | |
|---|---|---|---|
| `Ins` append | `Ctrl+D` delete | `Ctrl+R` recall | `Ctrl+Alt+R` recall all |
| `Ctrl+Home` / `Ctrl+End` top / bottom | `Ctrl+G` go to record | `Ctrl+F` / `Ctrl+S` find / seek | `F2` / `Shift+F2` browse / form |
| `Ctrl+C` copy record | `Ctrl+V` paste | `Ctrl+Alt+A` paste append | `Ctrl+Z` undo |
| `F5` refresh | `F12` commit | | |

## Requirements
- Windows, **.NET Framework 4.7.2**
- The **X# runtime** (XSharp.Core / Rdd / RT / Data / MacroCompiler). The macro compiler is needed for filters, scopes,
  replace expressions and index creation.

## Building
The repository contains both a Visual Studio and an XIde project:

| IDE | Open | Notes |
|---|---|---|
| Visual Studio (with the X# extension) | `FabDBFEdEnh.sln` | NuGet packages are restored automatically |
| XIde | `FabDBFEdEnh.xiproj` | uses the DLLs in `FabDBFEdEnh\lib` |

```
msbuild FabDBFEdEnh.sln -restore
```

The executable is `FabDBFEdEnh\bin\Debug\FabDBFEdEnh.exe`.

> A new source file has to be added to **both** project files (`FabDBFEdEnh.xsproj` and `FabDBFEdEnh.xiproj` / `FabDBFEdEnh.xiapp`).

## Repository layout
```
FabDBFEdEnh.sln / FabDBFEdEnh.xiproj      solution (VS) and project (XIde)
FabDBFEdEnh\
    FabDBFEdEnh.xsproj / .xiapp           project (VS) and application (XIde)
    *.prg                                 sources
    *.resx                                form resources (Visual Studio designer)
    Resources\                            compiled form resources (XIde)
    lib\                                  ICSharpCode.TextEditorEx, Newtonsoft.Json (XIde; Visual Studio uses NuGet)
```

## Not implemented yet
Some menu entries are placeholders: scoped delete, cut record, DBClipboard link, associate, DBCalc, DBRegEx, DBSort,
DBTotal, DBValidation, relations, text file editor, database list, generate create PRG / DBF description.

## Credits
- Based on [FabDBFEd](https://github.com/FabToys/FabDBFEd) by Fabrice Foray.
- Extended into a dBAdministrator-style editor in a German fork by Horst Korak (thanks to him) , then translated to English, fixed and extended here.

## Third party components
| Component | License |
|---|---|
| [X#](https://www.xsharp.eu/) runtime | Apache License 2.0 |
| [Newtonsoft.Json](https://www.newtonsoft.com/json) | MIT |
| [ICSharpCode.TextEditorEx](https://github.com/StefH/ICSharpCode.TextEditorEx) (SharpDevelop text editor) | LGPL-2.1-or-later |

## License
[MIT](LICENSE)
