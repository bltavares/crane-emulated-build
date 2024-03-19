# Emulated Nix Rust compilation troubleshooting

This is a troubleshooting repository for figuring out why `cargo-nextest` can't run tests on a emulated environment.

Instead of creating a `flake.nix` with cross-compilation, we'd instead run the `nix build` process with a different architecture emulated using `qemu` with the `binfmt_misc` kernel option.

This way, if we are on the same architecture system, we'll be using the tools without emulation, but we can still create binaries from other architectures using the emulated toolchain.

This avoid the case of cross-compilation configuration with `--target` changes, as well as cross-compiling to the host system. For example, if we define `.#packages.aarch64-linux.default` to be cross-compiled always, it would be doing cross-compilation on a `aarch64` host. The alternative is some `nix` magic ✨ with `system.crossPkgs` mangling with fallbacks to `system.packages`, that I'd like to avoid writing at all.

So far, having `qemu` configured on the host can already run cross-architecture binaries, and produce cross-architecture artifacts, such as:

```sh
nix shell nixpgs#hello --system aarch64-linux
nix shell nixpgs#hello --system x86_64-linux
```

But, it is having errors with `cargo` and `cargo-nextest` on Linux 🙁.
This error prevents using `cargo-nextest` with Github Actions, as it only offers hosted Linux AMD64 runners for free (unless you self-host an ARM64 runner youself).

## What I've learned so far

1. The intermediate artifacts of `cargo nextest` generate valid binaries with the emulated toolchain
    - But calling causes errors that are likely issues calling `exec` on their [executable double](https://github.com/nextest-rs/nextest/blob/890f1fdf6f72799ef81238e14bf83898fa4e3a80/cargo-nextest/src/double_spawn.rs#L30), which bypasses `binfmt_misc`
    - The name of the error is an entrypoint [when calling itself](https://github.com/nextest-rs/nextest/blob/890f1fdf6f72799ef81238e14bf83898fa4e3a80/nextest-runner/src/double_spawn.rs#L42-L43)
    - TODO :soon:: Open an issue on https://github.com/nextest-rs/nextest/

2. Most `qemu-static` emulation will succesfully produce binaries with the emulated toolchain
    - Except for NixOS `qemu` emulation, that can't link to the `rust-std` results
    - It seems that the resulting `symbols.so` from `rustc` is partially broken [ref [#1](https://github.com/rust-lang/cargo/issues/8239?utm_source=pocket_saves) [#2](https://github.com/rust-lang/rust/pull/111351?utm_source=pocket_saves)]
    - Using `rustc -C save-temps main.rs` allows inspecting of `symbols.so`, which reports the right arch under `file`, but fails to be parsed by `nm` or `objdump`.
    - TODO :soon:: Open an isso on https://github.com/nixos/nixpkgs

## Non Flake mode (simplest)

Ensure you have an emulated cross-architecture `binfmt_misc` on your host. Then build a empty `rust` file.


```sh
if [[ $(uname -m) == "arm64" || $(uname -m) == "aarch64" ]]; then
    emulated="x86_64-linux";
else
    emulated="aarch64-linux";
fi

nix-build non-flake.nix --argstr system $emulated
```


### Environment table

#### `nix-build` 

Almost all environment using the host `qemu-static` emulation will produce binaries using the emulated toolchain.

The exception is running NixOS as the host (eg: VM), where ~~(for some reason too arcane for me)~~ will break the `cc` on the emulated toolchain with [unrecognized symbol formats](#nixos-vm-errors).

| System         | Architecture        | Target                     | Works? |
| -------------- | ------------------- | -------------------------- | ------ |
| Darwin         | aarch64 (m1)        | x86_64 (rosetta)           | Yes ✅  |
| Linux (NixOS)  | amd64 (proxmox/lxc) | aarch64 (host qemu-static) | Yes ✅  |
| Linux (NixOS)  | amd64 (proxmox/vm)  | aarch64 (qemu)             | No  ❌  |
| Linux (NixOS)  | aarch64 (docker)    | x86_64 (host qemu)         | Yes ✅  |
| Linux (Ubuntu) | aarch64 (docker)    | x86_64 (host qemu)         | Yes ✅  |
| Linux (Ubuntu) | x86_64 (docker)     | aarch64 (host qemu)        | Yes ✅  |

## Crane build (flake/complete)

### Generating the project

This project was generated using [crane](https://crane.dev) quick-start template. No additional changes were applied either on `.nix` or the Rust project.

```bash
nix flake init -t github:ipetkov/crane#quick-start
nix flake check
```

### Environment table

#### `nix run` or `nix build`

Almost all environment using the host `qemu-static` emulation will produce binaries using the emulated toolchain.

The exception is running NixOS as the host (eg: VM), where ~~(for some reason too arcane for me)~~ will break the `cc` on the emulated toolchain with [unrecognized symbol formats](#nixos-vm-errors).

| System         | Architecture        | Target                     | Works? |
| -------------- | ------------------- | -------------------------- | ------ |
| Darwin         | aarch64 (m1)        | x86_64 (rosetta)           | Yes ✅  |
| Linux (NixOS)  | amd64 (proxmox/lxc) | aarch64 (host qemu-static) | Yes ✅  |
| Linux (NixOS)  | amd64 (proxmox/vm)  | aarch64 (qemu)             | No  ❌  |
| Linux (NixOS)  | aarch64 (docker)    | x86_64 (host qemu)         | Yes ✅  |
| Linux (Ubuntu) | aarch64 (docker)    | x86_64 (host qemu)         | Yes ✅  |
| Linux (Ubuntu) | x86_64 (docker)     | aarch64 (host qemu)        | Yes ✅  |

#### `craneLib.cargoTest`

Almost all environment using the host `qemu-static` emulation will produce binaries using the emulated toolchain.

The exception is running NixOS as the host (eg: VM), where ~~(for some reason too arcane for me)~~ will break the `cc` on the emulated toolchain with [unrecognized symbol formats](#nixos-vm-errors).

:warning: Sometimes, on a derivation shell, you'll get some `cc` errors which disapears after a few runs. It does not happen when running `nix flake check` with a `craneLib.cargoTest` tho.

| System         | Architecture        | Target                     | Works? |
| -------------- | ------------------- | -------------------------- | ------ |
| Darwin         | aarch64 (m1)        | x86_64 (rosetta)           | Yes ✅  |
| Linux (NixOS)  | amd64 (proxmox/lxc) | aarch64 (host qemu-static) | Yes ✅  |
| Linux (NixOS)  | amd64 (proxmox/vm)  | aarch64 (qemu-static)      | No  ❌  |
| Linux (NixOS)  | aarch64 (docker)    | x86_64 (host qemu)         | Yes ✅  |
| Linux (Ubuntu) | aarch64 (docker)    | x86_64 (host qemu)         | Yes ✅  |
| Linux (Ubuntu) | x86_64 (docker)     | aarch64 (host qemu)        | Yes ✅  |

#### `craneLib.cargoNextest`

❌ This is the main point of investigation, as `cargo nextest` has some nice speedup features, but it's causing problems when running in an emulated environment.

Running the resulting binaries under `target/debug/deps/my-create-*` will work on the host or on the emulated toolchain. So the issue seems to be when `cargo-nextest` execute/load the tests with some additional fork calls.

The tool will compile the test into separate tests, and this seems to be the issue.
Somethign related to `patchelf`? `LD_LIBRARY_PATH`? etc.

| System         | Architecture                    | Target                     | Works? |
| -------------- | ------------------------------- | -------------------------- | ------ |
| Darwin         | aarch64 (m1)                    | x86_64 (rosetta)           | Yes ✅  |
| Linux (NixOS)  | amd64 (proxmox/lxc priviledged) | aarch64 (host qemu-static) | No  ❌  |
| Linux (NixOS)  | amd64 (proxmox/vm)              | aarch64 (qemu-static)      | No  ❌  |
| Linux (NixOS)  | aarch64 (docker)                | x86_64 (host qemu)         | No  ❌  |
| Linux (Ubuntu) | aarch64 (docker)                | x86_64 (quemu)             | No  ❌  |
| Linux (Ubuntu) | x86_64 (docker)                 | aarch64 (quemu)            | No  ❌  |


## Does my system already support emulated cross-architecture execution?

You can test it by attempting to run a binary built for another architecture.

```sh
nix shell nixpgs#hello --system aarch64-linux
nix shell nixpgs#hello --system x86_64-linux
```

## Troubleshooting on a NixOS (VM)

Option A) A pre-built `amd64` NixOS VM for Proxmox is available on [Release #4](https://mynixos.com/bltavares/virtual/versions)
Log in with `bltavares` and password `nixos`.

Option B) Choose your favorite virtualization mechanism and generator. 

Ensure to include the following NixOS module when building to have `qemu` emulation support, as well as necessary Nix packages:
```nix
{pkgs, ...}: {
    boot.binfmt.emulatedSystems = ["aarch64-linux"];
    environment.packages = [
        pkgs.git
        pkgs.curl
    ];
}
```

1. Clone this repo on a new VM

Give it at least `4Gb` as it will likely compile `rust` from scratch.

```bash
git clone https://github.com/bltavares/crane-emulated-build
cd crane-emulated-build
```

2. Run the check with the current architecture

```bash
nix flake check -L
```

3. Run the check with a cross-architecture emulated

```bash
if [[ $(uname -m) == "arm64" || $(uname -m) == "aarch64" ]]; then
    emulated="x86_64-linux";
else
    emulated="aarch64-linux";
fi

nix flake check -L --system $emulated
```

## Troubleshooting with Docker (NixOS)

1. Get a Docker machine with support binfmt_misc support for aarch64 and x86_64.
   Projects such as Docker Desktop or Rancher Desktop have this provided by default.
   Otherwhise install with a `--priviledged` container on the Docker host.
```sh
# https://github.com/tonistiigi/binfmt
docker run --privileged --rm tonistiigi/binfmt --install all
```

2. Attempt a same platform build

```bash
docker run --rm -ti -v ${PWD}:/workspace --workdir /workspace nixos/nix \
  nix --extra-experimental-features nix-command --extra-experimental-features \
   flake check -L
```

3. Attempt emulated build

```bash
if [[ $(uname -m) == "arm64" || $(uname -m) == "aarch64" ]]; then
    emulated="x86_64-linux";
else
    emulated="aarch64-linux";
fi

docker run --rm -ti -v ${PWD}:/workspace --workdir /workspace nixos/nix \
  nix --extra-experimental-features nix-command --extra-experimental-features \
   flake check -L --system $emulated
```

## Troubleshooting with Docker (Ubuntu)

1. Get a Docker machine with support binfmt_misc support for aarch64 and x86_64.
   Projects such as Docker Desktop or Rancher Desktop have this provided by default.
   Otherwhise install with a `--priviledged` container on the Docker host.
```sh
# https://github.com/tonistiigi/binfmt
docker run --privileged --rm tonistiigi/binfmt --install all
```

2. Build an environment similar to Github Actions

This `Dockerfile` will attempt to run emulated cross-platform programs to ensure the Docker host is properly configured.
It if fails to build, revisit the previous step.

```bash
git clone https://github.com/bltavares/crane-emulated-build
cd crane-emulated-build
docker build . -t troubleshoot
```

3. Attempt a same platform build

```bash
docker run --rm -ti -v ${PWD}:/workspace --workdir /workspace troubleshoot \
  nix flake check -L
```

4. Attempt emulated build

```bash
if [[ $(uname -m) == "arm64" || $(uname -m) == "aarch64" ]]; then
    emulated="x86_64-linux";
else
    emulated="aarch64-linux";
fi

docker run --rm -ti -v ${PWD}:/workspace --workdir /workspace troubleshoot \
  nix flake check -L --system $emulated
```


### Troubleshoot shell

To evaluate the project locally, we can trigger a `nix repl` to reload quickly the `.nix` config.

```bash
docker run --rm -ti -v ${PWD}:/workspace --workdir /workspace troubleshoot
# [docker $] nix repl
## nix-repl > :lf .
## nix-repl > :sh outputs.checks.aarch64-linux.my-crate-nextest
### cargo clean
### cargo nextest run 
### exit
## nix-repl > :sh outputs.checks.x86_64-linux.my-crate-nextest
### cargo clean 
### cargo nextest run
### exit
```

## Errors

### NixOS VM errors

Using any of these commands on a fresh built NixOS VM, the linker does not work with the produced `rustc` symbols.

- `nix build --system aarch64-linux`
- `nix build .#packages.aarch64-linux.default`
- `nix shell --system aarch64-linux nixpkgs#cargo nixpkgs#rustc nixpkgs#gcc --command cargo build`

Produces the following error about `/build/rustcdhlbOQ/symbols.o: file not recognized: file format not recognized`, despite all tools resolving to an `aarch64` version.

<details>
<summary>Debug log</summary>

```text
error: builder for '/nix/store/qq8nx7491gaxinw1gs1xy7vxpqqvb0wj-project-deps-0.1.0.drv' failed with exit code 101;
last 10 log lines:
> ++ command cargo check --release --locked --all-targets
>    Compiling project v0.1.0 (/build/source)
> error: linking with `cc` failed: exit status: 1
>   |
>   = note: LC_ALL="C" PATH="/nix/store/p6g5ddgakhq393kyvbfwll5lc2n2yjdb-rust-stable-with-components-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/bin:/nix/store/p6g5ddgakhq393kyvbfwll5lc2n2yjdb-rust-stable-with-components-2024-02-08/bin:/nix/store/554m9gj7cd3qc7d9yyhvrw6l5gxwsf84-rsync-3.2.7/bin:/nix/store/jd6p89ryp975qmnsmpkwmml80pj32vi8-zstd-1.5.5-bin/bin:/nix/store/xm5lc0lhgjhqz5hjz6dcnllvbdb1qdnq-zstd-1.5.5/bin:/nix/store/z7abiwmqsg4m7d877sq1dinbxxsgg5jr-patchelf-0.15.0/bin:/nix/store/44di4gvw6lydf0hm9105palmlsdyvq5w-gcc-wrapper-13.2.0/bin:/nix/store/yw0pwdr8qm66l1b7s62zgczz37fg95ri-gcc-13.2.0/bin:/nix/store/a7zychff4w2w5ifjmli75h66adypvgh4-glibc-2.38-44-bin/bin:/nix/store/77fyfwmz29cz9j5x6yw2wrlm4rvasldv-coreutils-9.4/bin:/nix/store/bfvghacf729z1xnbkbznavv1312nshdz-binutils-wrapper-2.41/bin:/nix/store/f5xp690hwgqrvglkv61d4xcfqiijzmiq-binutils-2.41/bin:/nix/store/77fyfwmz29cz9j5x6yw2wrlm4rvasldv-coreutils-9.4/bin:/nix/store/ry6g1kym7g3i8813msq7b0gzqbdj1rfk-findutils-4.9.0/bin:/nix/store/5jpf44fy67dxhiwczcjc9w47hi96bm3q-diffutils-3.10/bin:/nix/store/jcpl9xd17v9c8aqkdwakhw3mymmagshp-gnused-4.9/bin:/nix/store/9fg6lk707pjy1k4hc3sx53lifhg1h09g-gnugrep-3.11/bin:/nix/store/w4b5hcaxh9jyr12bkms2i9kbksf7fax4-gawk-5.2.2/bin:/nix/store/f1w49nm88pnx65s4zw1azkxklndnw3sp-gnutar-1.35/bin:/nix/store/f79a7k1p7dc2cnkz0q5h6lqg48h1hbkc-gzip-1.13/bin:/nix/store/8h2cb2v7215i8awk2i1k702xcvr2d1zk-bzip2-1.0.8-bin/bin:/nix/store/qzi7n8bb148ccnkdkniq8m7y3jp37wvq-gnumake-4.4.1/bin:/nix/store/xz6h70zgmd6wf2931rdg5v4khnsxfg40-bash-5.2p26/bin:/nix/store/r7m8m864kbs5xsiw566fg2l64ya3v1zw-patch-2.7.6/bin:/nix/store/cfkpcy56gnr492mgnwrf3zpcqa9w1c1f-xz-5.6.0-bin/bin:/nix/store/1639yfqw64vivi4163ljawq8w8raypvj-file-5.45/bin" VSLANG="1033" "cc" "/build/rustcdhlbOQ/symbols.o" "/build/source/target/release/build/project-464a981a755b48f5/build_script_wnlwcrff0mph3zbkn87irc1cp7yjn8fd_dummy-464a981a755b48f5.build_script_wnlwcrff0mph3zbkn87irc1cp7yjn8fd_dummy.a86eb89a99210474-cgu.0.rcgu.o" "/build/source/target/release/build/project-464a981a755b48f5/build_script_wnlwcrff0mph3zbkn87irc1cp7yjn8fd_dummy-464a981a755b48f5.2dl777e3atnxv5yr.rcgu.o" "-Wl,--as-needed" "-L" "/build/source/target/release/deps" "-L" "/nix/store/p6g5ddgakhq393kyvbfwll5lc2n2yjdb-rust-stable-with-components-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib" "-Wl,-Bstatic" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/libstd-f4199621953e7607.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/libpanic_unwind-e0e3d3faaf87360b.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/libobject-b2591da5e9af8578.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/libmemchr-376f0f08e66e2a65.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/libaddr2line-ae0539bce548f90a.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/libgimli-d0f17aeffa5441ba.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/librustc_demangle-6f11dc0469c54fe0.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/libstd_detect-4afd6d84ddcb4b48.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/libhashbrown-30f262069447efa6.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/librustc_std_workspace_alloc-4bd969144080e871.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/libminiz_oxide-f4f8c06b1309a72d.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/libadler-6b3c870eb06a61ea.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/libunwind-c6ac0ce51af891e1.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/libcfg_if-c1a3e231f365ae96.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/liblibc-4184ec847e3b3c7b.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/liballoc-9e5e6dc4af4b2100.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/librustc_std_workspace_core-e316337282479ddd.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/libcore-17162ff9cd38c97e.rlib" "/nix/store/lif9897amab4zlra3lflqk24h9zvxrh9-rust-std-stable-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib/libcompiler_builtins-e02be2d915b30a04.rlib" "-Wl,-Bdynamic" "-lgcc_s" "-lutil" "-lrt" "-lpthread" "-lm" "-ldl" "-lc" "-Wl,--eh-frame-hdr" "-Wl,-z,noexecstack" "-L" "/nix/store/p6g5ddgakhq393kyvbfwll5lc2n2yjdb-rust-stable-with-components-2024-02-08/lib/rustlib/aarch64-unknown-linux-gnu/lib" "-o" "/build/source/target/release/build/project-464a981a755b48f5/build_script_wnlwcrff0mph3zbkn87irc1cp7yjn8fd_dummy-464a981a755b48f5" "-Wl,--gc-sections" "-pie" "-Wl,-z,relro,-z,now" "-nodefaultlibs"
>   = note: /build/rustcdhlbOQ/symbols.o: file not recognized: file format not recognized
>           collect2: error: ld returned 1 exit status
```
</details>

### Ubuntu or Nix containers
The error can be seen on [Github Actions](https://github.com/bltavares/banana/actions/runs/8225085891/job/22489701115) logs.

<details>
<summary>Debug log</summary>

```text
> ++ command cargo nextest run --cargo-profile release
>    Compiling project v0.1.0 (/build/source)
>     Finished release [optimized] target(s) in 5.84s
> error: creating test list failed
>
> Caused by:
>   for `project`, command `/build/source/target/release/deps/project-f15c34dc6dacf9a1 --list --format terse` exited with code 1
> --- stdout:
> Error while loading __double-spawn: No such file or directory
>
> --- stderr:
>
> ---
```
</details>


## References 

So far, these are some links that helpmed me figure out the emulated toolchain process, but not cover all of the issues yet.

- https://discourse.nixos.org/t/nix-github-actions-aarch64/11034/5?u=bltavares&utm_source=pocket_saves
- https://discourse.nixos.org/t/best-practices-for-building-aarch64-linux-pkgs-on-a-x86-64-linux-system/1697/2?u=bltavares
- https://discourse.nixos.org/t/how-do-i-get-my-aarch64-linux-machine-to-build-x86-64-linux-extra-platforms-doesnt-seem-to-work/38106/12?u=bltavares
- https://github.com/nix-community/naersk/issues/181?utm_source=pocket_saves#issuecomment-874352470
- https://github.com/numtide/system-manager/pull/44/files
- https://matklad.github.io//2022/03/14/rpath-or-why-lld-doesnt-work-on-nixos.html?utm_source=pocket_saves
- https://github.com/pop-os/xdg-desktop-portal-cosmic/pull/10/files
- https://github.com/mirkolenz/flocken?tab=readme-ov-file#flockenlegacypackagessystemmkdockermanifest
