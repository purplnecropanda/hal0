"""podman_introspect — read-only podman introspection through the ROOTFUL
context slots actually use (O12, halo143/halo150 deploy finding).

Slots run under ROOTFUL podman: Quadlet units under ``/etc/containers/systemd/``
(see :mod:`hal0.providers.container` + the ``hal0-systemctl`` write-quadlet
seam), populating root's podman image/container store. Post-P3-perms,
``hal0-api`` itself runs as the unprivileged ``hal0`` service user, so a bare
``podman images``/``podman ps`` call issued FROM hal0-api hits hal0's own
ROOTLESS store — a completely different store from the one slots populate.
Confirmed on deployed boxes: backends report ``"installable"`` even though
the image is present (in root's store), and any probe keyed off hal0's
rootless ``HOME`` is fragile. O12 fixes the actual cause by asking root's
store directly.

This module is the ONE place call sites route rootful podman reads through,
so nobody hand-rolls the ``sudo -n`` argv. The helper location follows
:mod:`hal0.config.paths`, which keeps the seam usable both on the upstream FHS
install and on NixOS where the shipped release tree lives in the Nix store.
"""

from __future__ import annotations

import shutil
import subprocess
from collections.abc import Callable
from dataclasses import dataclass
from typing import Literal

from hal0.config import paths
from hal0.system.seam import is_hal0_service_user

#: Installed path of the read-only podman introspection seam (O12).
#: Resolve through the FHS/Nix path layer rather than hard-coding /usr/lib/hal0.
SEAM_BIN = str(paths.lib() / "bin" / "hal0-podman-ro")

PodmanContext = Literal["rootful", "rootless"]

_RunFn = Callable[..., "subprocess.CompletedProcess[str]"]


@dataclass(frozen=True)
class PodmanImagesResult:
    """``podman images`` output + which store it actually came from."""

    repos: set[str]
    context: PodmanContext


def _seam_argv(*verb: str) -> list[str]:
    return ["sudo", "-n", SEAM_BIN, *verb]


def _run(
    run: _RunFn, argv: list[str], *, timeout: float
) -> subprocess.CompletedProcess[str] | None:
    try:
        return run(argv, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None


def _parse_repos(stdout: str) -> set[str]:
    return {line.strip() for line in stdout.splitlines() if line.strip() and line != "<none>"}


def images(
    *,
    run: _RunFn = subprocess.run,
    which: Callable[[str], str | None] | None = None,
    is_hal0_user: Callable[[], bool] = is_hal0_service_user,
    timeout: float = 10.0,
) -> PodmanImagesResult | None:
    """Return the local image set, preferring root's store when reachable."""
    if is_hal0_user():
        proc = _run(run, _seam_argv("images"), timeout=timeout)
        if proc is not None and proc.returncode == 0:
            return PodmanImagesResult(repos=_parse_repos(proc.stdout), context="rootful")

    which_fn = which or shutil.which
    podman = which_fn("podman")
    if podman is None:
        return None
    proc = _run(run, [podman, "images", "--format", "{{.Repository}}"], timeout=timeout)
    if proc is None or proc.returncode != 0:
        return None
    return PodmanImagesResult(repos=_parse_repos(proc.stdout), context="rootless")


__all__ = ["SEAM_BIN", "PodmanContext", "PodmanImagesResult", "images"]
