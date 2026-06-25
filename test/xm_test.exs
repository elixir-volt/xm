defmodule XMTest do
  use ExUnit.Case, async: true

  import XM

  doctest XM

  test "builds XML with element syntax, attributes, loops, and escaped text" do
    pages = ["/", "/about/?x=1&y=2"]
    site_url = "https://example.com"

    xml =
      document do
        urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
          for page <- pages do
            url do
              loc(site_url <> page)
              lastmod(Date.utc_today())
            end
          end
        end
      end

    assert xml =~ ~s(<?xml version="1.0"?>)
    assert xml =~ ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">)
    assert xml =~ ~s(<loc>https://example.com/about/?x=1&amp;y=2</loc>)
    assert xml =~ ~s(<lastmod>#{Date.utc_today()}</lastmod>)
  end

  test "supports cdata, comments, and tree nodes" do
    [entry] =
      tree do
        entry do
          title("Hello")
          comment("safe note")

          content(type: "html") do
            cdata("<p>Hello</p>")
          end
        end
      end

    assert XM.render(entry) =~ "<![CDATA[<p>Hello</p>]]>"
    assert XM.render(entry) =~ "<!--safe note-->"
    assert XM.render(entry) =~ ~s(<content type="html">)
  end

  test "supports dynamic tags, namespace helpers, and iodata rendering" do
    [node] =
      tree do
        tag(XM.qname(:media, :thumbnail), [
          XM.xmlns(:media, "https://example.com/media"),
          url: "https://example.com/image.png"
        ])
      end

    assert node == {
             "media:thumbnail",
             [
               {"xmlns:media", "https://example.com/media"},
               {"url", "https://example.com/image.png"}
             ],
             []
           }

    assert node |> XM.render_iodata() |> IO.iodata_to_binary() =~ "<media:thumbnail"
  end

  test "raises clear errors for invalid documents" do
    assert_raise XM.Error, ~r/requires a root element/, fn ->
      XM.render([])
    end

    assert_raise XM.Error, ~r/exactly one root element/, fn ->
      tree do
        one()
        two()
      end
      |> XM.render()
    end
  end

  test "raises idiomatic XM errors for invalid names, attributes, and text" do
    assert_raise XM.Error, ~r/invalid XML name/, fn ->
      XM.element("bad name")
    end

    assert_raise XM.Error, ~r/XML attributes must be/, fn ->
      XM.element(:item, [:not_a_pair])
    end

    assert_raise XM.Error, ~r/cannot convert/, fn ->
      XM.text(%{not: :stringable})
    end
  end

  test "supports conditionals" do
    include? = System.unique_integer() != 0

    xml =
      document do
        feed do
          if include? do
            title("Visible")
          else
            title("Hidden")
          end
        end
      end

    assert xml =~ "<title>Visible</title>"
    refute xml =~ "Hidden"
  end
end
