# solps-grids

This repository lets you design SOLPS-ITER grids with the **DivGeo** GUI on a Mac
and run everything else (Carre, Triang, Uinp, B2.5/Eirene) on a headless Linux
cluster. The repository carries the files between the two machines. It holds the
DivGeo designs, the equilibria they use, and the grids Carre makes from them, plus
the scripts that connect DivGeo and SOLPS on each side.

```
 Mac (design)                       this repository (git)                Linux (compute)
 ──────────────                     ─────────────────────────────        ─────────────────────────
 bin/dg ── DivGeo kit ──edit──────▶ devices/<DEVICE>/cases/<case>/ ──▶ bin/grid-import → lns
                                        .dg .dgo .str .trg .equ          carre -  (P, G, C, T)
 File|Import|Mesh ◀──── git pull ── devices/<DEVICE>/meshes/<case>/ ◀── bin/grid-export
                                        .vNNN.sno .vNNN.geo              then Uinp, Triang, B2.5 ...
                                    devices/<DEVICE>/equilibria/   ◀── e2d (EFIT → .equ)
```

The Mac needs no SOLPS-ITER checkout: DivGeo is built from its own repository.

## Repository layout

| Path | Contents | Written by |
|---|---|---|
| `devices/<DEVICE>/equilibria/` | Equilibria in DivGeo format (`*.equ`), optionally with their sources (EFIT g-files, ...) | you: `e2d` etc. on Linux |
| `devices/<DEVICE>/templates/` | Wall contours and other DivGeo templates (`*.itp`, `*.ogr`, ...) | you, DivGeo |
| `devices/<DEVICE>/templates/triang/` | Triang templates `template.*.tria` | `grid-export --triang` |
| `devices/<DEVICE>/cases/<case>/` | One DivGeo design: `<case>.dg` (model), `<case>.dgo/.str/.trg` (File\|Output), the equilibrium it uses | DivGeo through `bin/dg` |
| `devices/<DEVICE>/meshes/<case>/` | Grids stored by Carre: `<case>.vNNN.sno` (DivGeo format), `<case>.vNNN.geo` (B2.5 format), `CARRE.HISTORY` | `grid-export` |
| `DIVGEO_VERSION` | DivGeo version the designs are made with | you |
| `local.env` | Per-machine settings (git-ignored); see `local.env.example` | you |
| `.dgkit/` | The DivGeo program built on this Mac (git-ignored) | `bin/build-dg-kit` |

`DEVICE` is the tokamak name (`iter`, `upgrade`, `jet`, `d3d`, `tcv`, ...). Use the
same name on both sides, with at most 12 characters: B2.5 truncates longer names.
Device and case names may contain only letters, digits, `.`, `_` and `-`, because
DivGeo and SOLPS' `lns` split file names on spaces.

## Setup

### Mac (design side)

1. Install the prerequisites:
   - the Xcode command line tools (`xcode-select --install`);
   - **XQuartz** from https://www.xquartz.org. Log out and back in afterwards.
   - [MacPorts](https://www.macports.org), and then:
     ```sh
     sudo port install motif xorg-libXp gmake
     ```
2. Clone this repository and build DivGeo:
   ```sh
   git clone git@github.com:<owner>/solps-grids.git
   cd solps-grids
   bin/build-dg-kit
   ```
   This clones DivGeo at the version in `DIVGEO_VERSION` and builds it, which takes
   a few seconds. It then installs the program into `.dgkit/`. No SOLPS environment
   is used.
   - By default the source is `https://github.com/iterorganization/DivGeo.git`, or
     `$SOLPSTOP/modules/DivGeo` if a SOLPS-ITER checkout is set up. `--src` or
     `DIVGEO_SRC` choose another source.
   - Run `bin/build-dg-kit --help` for all the options.
3. Optionally, `cp local.env.example local.env` and set `DEVICE`, so that you don't
   have to pass `-d` every time.

**Another Mac without MacPorts.** `bin/build-dg-kit --bundle --prefix ~/DivGeo-kit`
makes a self-contained kit: it includes the 29 MacPorts libraries and the X11 data
it needs, about 12 MB. Copy that folder to the other Mac and set `DG_KIT` there to
where you put it. That Mac needs only XQuartz, an Apple silicon CPU, and at least
the macOS version the kit was built on (both are recorded in the kit's `VERSION`
file).

### Linux (compute side)

1. Use the SOLPS-ITER installation that runs the simulations. Its DivGeo should
   match `DIVGEO_VERSION`. Check with
   `git -C $SOLPSTOP/modules/DivGeo describe --tags`; `grid-import` warns if they
   differ. This matters because the variables DivGeo writes into `.dgo` files must be
   the ones Uinp expects.
2. Clone this repository anywhere, e.g. `git clone git@github.com:<owner>/solps-grids.git ~/solps-grids`.
3. In every shell where you use the scripts, load SOLPS first:
   ```csh
   source $SOLPSTOP/setup.csh
   ```
   The scripts are bash, but they work from tcsh. They only need the environment
   that `setup.csh` sets up.
4. Optionally, choose where the Carre work directories go (see
   [Configuration](#configuration)).

## Workflow

Examples use `DEVICE=iter` and a case called `mycase`.

**1. Equilibrium (Linux).** The equilibrium converters (`e2d`, `ids2dg`, ...) are
Fortran programs of SOLPS-ITER, so run them on the compute side and commit the result:
```csh
mkdir -p ~/solps-grids/devices/iter/equilibria
e2d g123456.01000 ~/solps-grids/devices/iter/equilibria/shot123456.equ
cd ~/solps-grids && git add devices/iter/equilibria && git commit -m "Equilibrium 123456" && git push
```

**2. Design (Mac).**
```sh
git pull
bin/dg -d iter mycase
```
DivGeo starts in `devices/iter/cases/mycase/`, and its file dialogs point into the
repository (see `bin/dg --help`). In DivGeo:
- load the equilibrium (File|Import|Equilibrium) and design the geometry;
- **File|Save** as `mycase.dg`;
- **File|Output**, which writes `mycase.dgo`, `mycase.str` and `mycase.trg`.

When you quit DivGeo, `bin/dg` makes the case portable:
- it copies the equilibrium into the case folder;
- it rewrites the absolute Mac paths in `mycase.dg` and `mycase.trg` so they are
  relative to the case folder.

Then commit and push:
```sh
git add devices/iter && git commit -m "mycase: first design" && git push
```

**3. Grid (Linux).**
```csh
cd ~/solps-grids && git pull
bin/grid-import -d iter mycase
cd $SOLPSWORK/grids/iter/mycase       # printed by grid-import
carre -                               # P: prepare, G: grid, C: convert, T: store, Q: quit
~/solps-grids/bin/grid-export -d iter mycase --commit && git -C ~/solps-grids push
```
- `grid-import` copies the case into the work directory and runs SOLPS' `lns` there.
  `lns` creates the `dg.*`, `uinput.*` and `param.dg` links and copies the design to
  `$DG/device/iter`, just as in the usual SOLPS workflow.
- `grid-export` copies the stored grids (`mycase.vNNN.sno/.geo`) and `CARRE.HISTORY`
  into `devices/iter/meshes/mycase/`.

**4. Check (Mac).** Run `git pull` and `bin/dg -d iter mycase`, then
**File|Import|Mesh**. The dialog opens in `devices/iter/meshes/mycase/`. If the grid
isn't right, change the design, File|Save + File|Output, push, and repeat from step 3.

**5. Simulation (Linux).** The rest works as usual in SOLPS-ITER: `uinp`, `triang`,
and the b2/Eirene run setup in the Carre work directory or a baserun directory. It
uses the files `lns` and Carre put in place. `grid-export --triang` also brings the
Triang templates (`template.*.tria`) back, so you can check them in DivGeo with
File|Import|Template.

## Configuration

Settings come from, in this order of precedence:
1. a command-line option;
2. an environment variable;
3. `local.env` in the repository root, which is git-ignored (start from
   `local.env.example`);
4. the built-in default.

| Setting | Side | Default | Meaning |
|---|---|---|---|
| `DEVICE` (`-d`) | both | — | Tokamak name, at most 12 characters |
| `DG_KIT` | Mac | `<repo>/.dgkit` | Where `build-dg-kit` installs DivGeo and `dg` finds it |
| `DIVGEO_SRC` (`--src`) | Mac | `$SOLPSTOP/modules/DivGeo` if present, else the GitHub URL | DivGeo git repository to build from |
| `MACPORTS_PREFIX` | Mac | `/opt/local` | MacPorts installation |
| `GRID_WORKDIR` | Linux | `$SOLPSWORK/grids` | Root of the Carre work directories |
| `-w WORKDIR` | Linux | — | Work directory for one case (`grid-import`, `grid-export`) |

### Carre work directories

`grid-import` and `grid-export` use the first of these that applies:
1. `-w WORKDIR`, used exactly as given;
2. `$GRID_WORKDIR/<DEVICE>/<case>`, if `GRID_WORKDIR` is set in the environment
   (`setenv GRID_WORKDIR /scratch/$USER/grids` in csh) or in `local.env`;
3. `$SOLPSWORK/grids/<DEVICE>/<case>`. `setup.csh` sets `SOLPSWORK` to
   `$SOLPSTOP/runs`, which git ignores, unless you set it yourself.

Use the same `-w` for `grid-export` as for `grid-import` if you gave one.

## Commands

| Command | Side | Purpose |
|---|---|---|
| `bin/build-dg-kit` | Mac | Build and install DivGeo (`--bundle` makes a self-contained kit) |
| `bin/dg [-d DEVICE] CASE` | Mac | Start DivGeo for a case; make it portable when DivGeo exits |
| `bin/dg [-d DEVICE] --fix CASE` | Mac | Only make the case portable (e.g. after copying files in by hand) |
| `bin/grid-import [-d DEVICE] [-w DIR] CASE` | Linux | Case → Carre work directory, then run `lns` |
| `bin/grid-export [-d DEVICE] [-w DIR] [--triang] [--commit] CASE` | Linux | Stored grids → `devices/<DEVICE>/meshes/<case>/` |

Every command accepts `--help`.

## Rules and pitfalls

- **Name the case files after the case:** `mycase.dg`, and File|Output then writes
  `mycase.dgo/.str/.trg`. `grid-import` looks for these names.
- **Always File|Output after changing the design.** The compute side uses only the
  output files, not `.dg`. `bin/dg` warns when `.dg` is newer than `.dgo`.
- **Don't commit links.** The links made by `lns` and SOLPS' own `dg` script hold
  absolute paths. They are git-ignored and get re-created on each machine.
- **Clear `CARRE_STOREDIR` on the compute side.** If it's set (SOLPS' ksh setup sets
  it, csh doesn't), `carre -` reads its input from there instead of the work
  directory. `grid-import` warns about it.
- **Keep one DivGeo version per repository** (`DIVGEO_VERSION`). When SOLPS-ITER on
  the cluster is updated, update the file and rebuild the kit on the Mac.
- **Mesh references in a `.dg`** point into `devices/<DEVICE>/meshes/`. So a design
  that references a mesh only finds it after `git pull` has brought that mesh in.

## Publishing on GitHub

Create an empty repository on GitHub first (private is recommended). Then, in this
directory:
```sh
git add -A && git commit -m "Initial solps-grids setup"
git branch -M main
git remote add origin git@github.com:<owner>/solps-grids.git
git push -u origin main
```

## Troubleshooting

- **`no DivGeo kit in .../.dgkit`:** run `bin/build-dg-kit` on this Mac, or set
  `DG_KIT`.
- **DivGeo doesn't open a window / `DISPLAY is not set`:** XQuartz is missing, or you
  haven't logged out and in since installing it.
- **`the equilibrium X is not in the case folder`** (`grid-import`): run
  `bin/dg --fix CASE` on the Mac, then commit and push.
- **`no stored grids`** (`grid-export`): use `T` (store) in `carre -` first.
- **DivGeo version warnings:** see "Keep one DivGeo version per repository" above.
