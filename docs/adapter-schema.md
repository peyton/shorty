# Adapter JSON Schema

Shorty adapters are JSON files that map canonical shortcut IDs to native app or
web-app actions. User adapters live in
`~/Library/Application Support/Shorty/Adapters/`, and generated adapters live in
`~/Library/Application Support/Shorty/AutoAdapters/`.

The schema below documents the stable file shape accepted by
`AdapterRegistry.validate(adapter:)`. It is intentionally strict: each adapter
must target one app identifier, include a display name, and define one mapping
per canonical shortcut ID at most.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://shorty.peyton.app/schemas/adapter.schema.json",
  "title": "Shorty Adapter",
  "type": "object",
  "additionalProperties": false,
  "required": ["appIdentifier", "appName", "source", "mappings"],
  "properties": {
    "appIdentifier": {
      "type": "string",
      "minLength": 1,
      "maxLength": 200,
      "description": "A macOS bundle identifier such as com.apple.Safari, or a web adapter identifier such as web:figma.com.",
      "not": {
        "pattern": "[\\s\\u0000-\\u001F/]"
      }
    },
    "appName": {
      "type": "string",
      "minLength": 1,
      "description": "The display name shown in Shorty settings."
    },
    "source": {
      "type": "string",
      "enum": [
        "builtin",
        "menuIntrospection",
        "llmGenerated",
        "community",
        "user"
      ]
    },
    "mappings": {
      "type": "array",
      "minItems": 1,
      "maxItems": 100,
      "items": {
        "$ref": "#/$defs/mapping"
      }
    }
  },
  "$defs": {
    "mapping": {
      "type": "object",
      "additionalProperties": false,
      "required": ["canonicalID", "method"],
      "properties": {
        "canonicalID": {
          "type": "string",
          "description": "One of Shorty's canonical shortcut IDs, such as focus_url_bar or command_palette."
        },
        "method": {
          "type": "string",
          "enum": ["keyRemap", "menuInvoke", "axAction", "passthrough"]
        },
        "nativeKeys": {
          "$ref": "#/$defs/keyCombo"
        },
        "menuTitle": {
          "type": "string",
          "minLength": 1,
          "maxLength": 200
        },
        "axAction": {
          "type": "string",
          "pattern": "^AX",
          "maxLength": 100
        },
        "context": {
          "type": "string",
          "minLength": 1,
          "maxLength": 100
        }
      },
      "allOf": [
        {
          "if": {
            "properties": { "method": { "const": "keyRemap" } }
          },
          "then": {
            "required": ["nativeKeys"],
            "not": {
              "anyOf": [
                { "required": ["menuTitle"] },
                { "required": ["axAction"] }
              ]
            }
          }
        },
        {
          "if": {
            "properties": { "method": { "const": "menuInvoke" } }
          },
          "then": {
            "required": ["menuTitle"],
            "not": {
              "anyOf": [
                { "required": ["nativeKeys"] },
                { "required": ["axAction"] }
              ]
            }
          }
        },
        {
          "if": {
            "properties": { "method": { "const": "axAction" } }
          },
          "then": {
            "required": ["axAction"],
            "not": {
              "anyOf": [
                { "required": ["nativeKeys"] },
                { "required": ["menuTitle"] }
              ]
            }
          }
        },
        {
          "if": {
            "properties": { "method": { "const": "passthrough" } }
          },
          "then": {
            "not": {
              "anyOf": [
                { "required": ["nativeKeys"] },
                { "required": ["menuTitle"] },
                { "required": ["axAction"] }
              ]
            }
          }
        }
      ]
    },
    "keyCombo": {
      "type": "object",
      "additionalProperties": false,
      "required": ["keyCode", "modifiers"],
      "properties": {
        "keyCode": {
          "type": "integer",
          "minimum": 0,
          "maximum": 255
        },
        "modifiers": {
          "type": "integer",
          "minimum": 0,
          "maximum": 15,
          "description": "Bitset: command=1, shift=2, option=4, control=8."
        }
      }
    }
  }
}
```

Before saving an adapter, Shorty also checks that every `canonicalID` exists in
the built-in canonical shortcut list and that no canonical shortcut appears more
than once in the same adapter.
