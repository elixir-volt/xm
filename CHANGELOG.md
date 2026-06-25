# Changelog

## Unreleased

## 0.2.0 - 2026-06-25

- Added namespace helpers with `qname/2`, `xmlns/1`, and `xmlns/2`.
- Added declarative `schema do ... end` metadata for root namespace and XSD location rendering.
- Added dotted namespace calls such as `image.image do ... end` for declared schema prefixes.
- Added `XM.validate!/2` for XSD validation through Erlang/OTP `:xmerl_xsd`.
- Added global `config :xm, validate: true` support for validating `document do ... end` at macro expansion configuration time.
- Documented iodata-first rendering with `tree do ... end |> XM.render_iodata()`.
- Added `%XM.Error{}` for idiomatic XML DSL errors.
- Improved validation for element names, attributes, text conversion, schema declarations, and schema validation.

## 0.1.0 - 2026-06-25

- Initial release with a Saxy-backed XML DSL.
- Added `document/2`, `tree/1`, `render/2`, and `render_iodata/2`.
- Added element, text, comment, CDATA, and dynamic tag helpers.
