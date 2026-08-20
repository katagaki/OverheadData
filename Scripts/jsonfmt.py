"""Serialises line JSON the way the hand-authored files are formatted:
4-space indent, but arrays of scalars stay on one line."""
import json


def _scalar(v):
    return v is None or isinstance(v, (int, float, str, bool))


def dumps(value, indent=4, level=0):
    pad, inner = " " * (indent * level), " " * (indent * (level + 1))
    if isinstance(value, dict):
        if not value:
            return "{}"
        items = [f'{inner}{json.dumps(k, ensure_ascii=False)}: '
                 f'{dumps(v, indent, level + 1)}' for k, v in value.items()]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(value, list):
        if not value:
            return "[]"
        if all(_scalar(v) for v in value):
            return "[" + ", ".join(json.dumps(v, ensure_ascii=False) for v in value) + "]"
        items = [inner + dumps(v, indent, level + 1) for v in value]
        return "[\n" + ",\n".join(items) + "\n" + pad + "]"
    return json.dumps(value, ensure_ascii=False)
