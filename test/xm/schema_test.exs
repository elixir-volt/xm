defmodule XM.SchemaTest do
  use ExUnit.Case, async: false

  import XM

  @moduletag :tmp_dir

  test "schema declarations inject namespaces and schema locations", %{tmp_dir: tmp_dir} do
    xsd = Path.join(tmp_dir, "note.xsd")

    xml =
      document do
        schema do
          default("urn:test", location: xsd)
          ns(:media, "urn:media", location: "media.xsd")
        end

        note do
          to("Alice")
          media.item("Image")
        end
      end

    assert xml =~ ~s(xmlns="urn:test")
    assert xml =~ ~s(xmlns:media="urn:media")
    assert xml =~ ~s(xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance")
    assert xml =~ ~s(urn:test #{xsd} urn:media media.xsd)
    assert xml =~ "<media:item>Image</media:item>"
  end

  test "validates XML with explicit schema option", %{tmp_dir: tmp_dir} do
    xsd = write_note_schema(tmp_dir)
    xml = ~s(<note xmlns="urn:test"><to>Alice</to></note>)

    assert XM.validate!(xml, schema: xsd) == xml
  end

  test "validates XML using declarative schema locations when configured by caller", %{
    tmp_dir: tmp_dir
  } do
    xsd = write_note_schema(tmp_dir)

    xml =
      document do
        schema do
          default("urn:test", location: xsd)
        end

        note do
          to("Alice")
        end
      end

    assert XM.validate!(xml) == xml
  end

  test "validates XML with noNamespaceSchemaLocation", %{tmp_dir: tmp_dir} do
    xsd = write_no_namespace_note_schema(tmp_dir)

    xml =
      ~s(<note xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="#{xsd}"><to>Alice</to></note>)

    assert XM.validate!(xml) == xml
  end

  test "raises XM.Error for invalid XML against XSD", %{tmp_dir: tmp_dir} do
    xsd = write_note_schema(tmp_dir)
    xml = ~s(<note xmlns="urn:test"><bad>Alice</bad></note>)

    assert_raise XM.Error, ~r/XML schema validation failed/, fn ->
      XM.validate!(xml, schema: xsd)
    end
  end

  test "raises XM.Error when validation has no schema" do
    assert_raise XM.Error, ~r/requires schema declarations or a :schema option/, fn ->
      XM.validate!(~s(<note><to>Alice</to></note>))
    end
  end

  test "compile-time config validates documents", %{tmp_dir: tmp_dir} do
    xsd = write_note_schema(tmp_dir)

    module =
      compile_document_module!(
        validate?: true,
        body:
          quote do
            schema do
              default("urn:test", location: unquote(xsd))
            end

            note do
              to("Alice")
            end
          end
      )

    assert module.document() =~ "<to>Alice</to>"
  end

  test "compile-time config raises when documents have no schema" do
    module =
      compile_document_module!(
        validate?: true,
        body:
          quote do
            note do
              to("Alice")
            end
          end
      )

    assert_raise XM.Error, ~r/requires schema declarations or a :schema option/, fn ->
      module.document()
    end
  end

  test "compile-time config raises when documents fail schema validation", %{tmp_dir: tmp_dir} do
    xsd = write_note_schema(tmp_dir)

    module =
      compile_document_module!(
        validate?: true,
        body:
          quote do
            schema do
              default("urn:test", location: unquote(xsd))
            end

            note do
              bad("Alice")
            end
          end
      )

    assert_raise XM.Error, ~r/XML schema validation failed/, fn ->
      module.document()
    end
  end

  test "compile-time config is captured when the document macro expands", %{tmp_dir: tmp_dir} do
    xsd = write_note_schema(tmp_dir)

    module =
      compile_document_module!(
        validate?: false,
        body:
          quote do
            schema do
              default("urn:test", location: unquote(xsd))
            end

            note do
              bad("Alice")
            end
          end
      )

    Application.put_env(:xm, :validate, true)

    assert module.document() =~ "<bad>Alice</bad>"
  after
    Application.delete_env(:xm, :validate)
  end

  test "raises XM.Error for malformed schemaLocation" do
    xml =
      ~s(<note xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="urn:test"><to>Alice</to></note>)

    assert_raise XM.Error, ~r/namespace\/location pairs/, fn ->
      XM.validate!(xml)
    end
  end

  defp compile_document_module!(opts) do
    validate? = Keyword.fetch!(opts, :validate?)
    body = Keyword.fetch!(opts, :body)
    module = Module.concat(__MODULE__, "Compiled#{System.unique_integer([:positive])}")
    previous = Application.get_env(:xm, :validate, :__unset__)

    Application.put_env(:xm, :validate, validate?)

    try do
      Module.create(
        module,
        quote do
          import XM

          def document do
            document do
              unquote(body)
            end
          end
        end,
        Macro.Env.location(__ENV__)
      )

      module
    after
      case previous do
        :__unset__ -> Application.delete_env(:xm, :validate)
        value -> Application.put_env(:xm, :validate, value)
      end
    end
  end

  defp write_note_schema(tmp_dir) do
    path = Path.join(tmp_dir, "note.xsd")

    File.write!(path, """
    <?xml version="1.0"?>
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:test" xmlns="urn:test" elementFormDefault="qualified">
      <xs:element name="note">
        <xs:complexType>
          <xs:sequence>
            <xs:element name="to" type="xs:string"/>
          </xs:sequence>
        </xs:complexType>
      </xs:element>
    </xs:schema>
    """)

    path
  end

  defp write_no_namespace_note_schema(tmp_dir) do
    path = Path.join(tmp_dir, "note-no-namespace.xsd")

    File.write!(path, """
    <?xml version="1.0"?>
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" elementFormDefault="qualified">
      <xs:element name="note">
        <xs:complexType>
          <xs:sequence>
            <xs:element name="to" type="xs:string"/>
          </xs:sequence>
        </xs:complexType>
      </xs:element>
    </xs:schema>
    """)

    path
  end
end
