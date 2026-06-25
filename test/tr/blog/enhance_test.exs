defmodule Tr.Blog.EnhanceTest do
  use ExUnit.Case, async: true

  alias Tr.Blog.Enhance

  test "slugify normalizes heading text" do
    assert Enhance.slugify("Hello World!") == "hello-world"
    assert Enhance.slugify("Core objects: Pods") == "core-objects-pods"
    assert Enhance.slugify("   ") == "section"
  end

  test "adds ids and hover anchors to headings and builds a toc" do
    {body, toc} = Enhance.process("<h2>Intro</h2><p>x</p><h3>Deep dive</h3>")

    assert body =~ ~s(<h2 id="intro">)
    assert body =~ ~s(<a class="tr-anchor" href="#intro")
    assert body =~ ~s(<h3 id="deep-dive">)

    assert [
             %{level: 2, id: "intro", text: "Intro", indent: 0},
             %{level: 3, id: "deep-dive", text: "Deep dive", indent: 1}
           ] = toc
  end

  test "deduplicates repeated heading ids" do
    {_body, toc} = Enhance.process("<h2>Setup</h2><h2>Setup</h2>")
    assert Enum.map(toc, & &1.id) == ["setup", "setup-2"]
  end

  test "strips inner markup for the slug and toc text" do
    {body, toc} = Enhance.process("<h5><strong>Hello</strong> there</h5>")
    assert body =~ ~s(id="hello-there")
    assert [%{text: "Hello there"}] = toc
  end

  test "turns GitHub-style alert blockquotes into callouts, keeping inner markup" do
    html = "<blockquote>\n<p>[!WARNING]\nNever run <code>rm -rf /</code>.</p>\n</blockquote>"
    {body, _toc} = Enhance.process(html)

    assert body =~ ~s(<div class="tr-callout tr-callout-warning">)
    assert body =~ ~s(<p class="tr-callout-title">Warning</p>)
    assert body =~ "<code>rm -rf /</code>"
    refute body =~ "[!WARNING]"
  end

  test "leaves ordinary blockquotes untouched" do
    {body, _toc} = Enhance.process("<blockquote>\n<p>just a quote</p>\n</blockquote>")
    assert body =~ "<blockquote>"
    refute body =~ "tr-callout"
  end

  test "folds kramdown image attribute lists onto the img tag" do
    # mirrors Earmark output: the literal {:...} text has escaped quotes
    html = ~s(<p><img src="/images/x.webp" alt="x" />{:class=&quot;mx-auto&quot;}</p>)
    {body, _toc} = Enhance.process(html)

    assert body =~ ~s(<img class="mx-auto" src="/images/x.webp" alt="x" />)
    refute body =~ "{:class"
    refute body =~ "&quot;"
  end

  test "keeps extra attributes (e.g. style) from the image attribute list" do
    html =
      ~s(<img src="/i/a.webp" alt="a">{:class=&quot;mx-auto&quot; style=&quot;max-height: 450px;&quot;})

    {body, _toc} = Enhance.process(html)

    assert body =~ ~s(class="mx-auto")
    assert body =~ ~s(style="max-height: 450px;")
    refute body =~ "{:"
  end

  test "no headings yields an empty toc and unchanged body" do
    assert {"<p>plain</p>", []} = Enhance.process("<p>plain</p>")
  end
end
