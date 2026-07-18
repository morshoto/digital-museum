"""Resolve bundled painting profiles without changing the public HTTP schema."""
from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re
import threading


PARAMETERS = ("brightness", "warmth", "abstraction", "motion", "tension")
ANCHOR_NAME = re.compile(r"^world-anchor__(\d+)__(\d+)__(\d+)\.png$")


@dataclass(frozen=True)
class PaintingProfile:
    id: str
    title: str
    artist: str
    resource_filename: str
    default_state: dict[str, float]
    palette: str
    brush: str
    structure: str
    prompt_bias: tuple[str, ...]

    @classmethod
    def from_json(cls, value: dict) -> PaintingProfile:
        visual = value["visualBias"]
        state = {key: float(value["defaultState"][key]) for key in PARAMETERS}
        if any(not 0 <= number <= 1 for number in state.values()):
            raise ValueError(f"painting profile {value.get('id')} has an unbounded defaultState")
        return cls(
            id=value["id"],
            title=value["title"],
            artist=value["artist"],
            resource_filename=value["resourceFilename"],
            default_state=state,
            palette=visual["palette"],
            brush=visual["brush"],
            structure=visual["structure"],
            prompt_bias=tuple(value["promptBias"]),
        )


@dataclass(frozen=True)
class PaintingInfluence:
    current: PaintingProfile
    target: PaintingProfile | None
    progress: float
    state_bias: float

    def adjusted_state(self, state: dict[str, float]) -> dict[str, float]:
        target = self.target or self.current
        progress = min(1, max(0, self.progress))
        bias = min(.2, max(0, self.state_bias))
        adjusted = {}
        for key in PARAMETERS:
            profile_value = self.current.default_state[key] * (1 - progress) + target.default_state[key] * progress
            adjusted[key] = state[key] * (1 - bias) + profile_value * bias
        return adjusted

    def prompt_fragment(self) -> str:
        if self.target is None or self.progress <= 0:
            return f"reference world: {self._profile_fragment(self.current)}"
        target_subject = self.target.prompt_bias[0]
        return (
            f"continuous painted bridge from {self.current.artist} to "
            f"{self.target.artist} {self.target.title}, target {self.progress:.2f}; "
            f"{target_subject}; {self.target.palette}"
        )

    @staticmethod
    def _profile_fragment(profile: PaintingProfile) -> str:
        return (
            f"{profile.artist} {profile.title}; {profile.prompt_bias[0]}; "
            f"{profile.palette}; {profile.brush}"
        )


class PaintingPromptResolver:
    """Maps resource and generated anchor filenames back to the shared catalog."""

    def __init__(self):
        self._profiles: tuple[PaintingProfile, ...] = ()
        self._state_bias = 0.0
        self._catalog_directory: Path | None = None
        self._lock = threading.Lock()

    def resolve(self, original_path: str | None) -> PaintingInfluence | None:
        if not original_path:
            return None
        path = Path(original_path).expanduser()
        with self._lock:
            catalog_path = path.parent / "catalog.json"
            if catalog_path.is_file():
                self._load(catalog_path)
            if not self._profiles:
                return None

            for profile in self._profiles:
                if path.name == profile.resource_filename and path.parent == self._catalog_directory:
                    return PaintingInfluence(profile, None, 0, self._state_bias)

            match = ANCHOR_NAME.fullmatch(path.name)
            if not match:
                return None
            current_index, target_index, progress_milli = map(int, match.groups())
            if current_index >= len(self._profiles) or target_index >= len(self._profiles):
                return None
            return PaintingInfluence(
                self._profiles[current_index],
                self._profiles[target_index],
                min(1, progress_milli / 1_000),
                self._state_bias,
            )

    def _load(self, path: Path) -> None:
        if self._catalog_directory == path.parent and self._profiles:
            return
        payload = json.loads(path.read_text())
        if payload.get("version") != 1:
            raise ValueError("unsupported painting catalog version")
        profiles = tuple(PaintingProfile.from_json(value) for value in payload["paintings"])
        if not profiles or len({profile.id for profile in profiles}) != len(profiles):
            raise ValueError("painting catalog must contain unique profiles")
        resources = {profile.resource_filename for profile in profiles}
        if len(resources) != len(profiles):
            raise ValueError("painting catalog must contain unique resource filenames")
        self._profiles = profiles
        self._state_bias = min(.2, max(0, float(payload["rotation"]["stateBias"])))
        self._catalog_directory = path.parent
