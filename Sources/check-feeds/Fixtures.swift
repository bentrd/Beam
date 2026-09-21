import Foundation

/// Feeds as they are found, not as they are specified. Each fixture is dirty in the ways its name says.
enum Fixtures {
    /// RSS 2.0: byte-order mark and a blank line before the declaration, HTML entities XML does not define, bare
    /// ampersands, a control character, CDATA, `content:encoded`, relative links, WordPress boilerplate, a repeated
    /// GUID, an item with no GUID, an item with nothing but a title and a date, campaign parameters, excerpt
    /// boilerplate, and an item dated in the future.
    static let dirtyRSS = "\u{FEFF}\n" + #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:atom="http://www.w3.org/2005/Atom">
    <channel>
      <title>Caf&eacute; &amp; Code &mdash; R&D notes</title>
      <link>https://blog.example.com/</link>
      <atom:link href="https://blog.example.com/feed" rel="self" type="application/rss+xml"/>
      <image><title>Not the feed title</title><url>/logo.png</url><link>https://blog.example.com/</link></image>
      <item>
        <title>Ben &amp; Jerry&rsquo;s&nbsp;guide to AT&T's &lt;dialog&gt; element, <em>really</em></title>
        <link>/posts/dialog?a=1&b=2</link>
        <guid isPermaLink="false">post-1</guid>
        <pubDate>Mon, 21 Sep 2026 09:30:00 +0200</pubDate>
        <description><![CDATA[<p>First&nbsp;paragraph with <a href="/x">a link</a> &amp; an entity.</p><script>alert("no")</script><p>Second[[BELL]] paragraph.</p><p>The post Ben &amp; Jerry&#8217;s guide appeared first on Café &amp; Code.</p>]]></description>
        <content:encoded><![CDATA[<p>First&nbsp;paragraph with <a href="/x">a link</a> &amp; an entity.</p><p>Second paragraph.</p><p>[[LONG]]</p>]]></content:encoded>
      </item>
      <item>
        <title>Duplicate of the first</title>
        <link>https://blog.example.com/posts/duplicate</link>
        <guid isPermaLink="false">post-1</guid>
      </item>
      <item>
        <title>No GUID here</title>
        <link>posts/no-guid</link>
        <dc:date>2026-09-20T08:00:00Z</dc:date>
        <description>Plain &lt;b&gt;escaped&lt;/b&gt; markup, 1 &lt; 2 and &unknownentity; stay readable.</description>
      </item>
      <item>
        <title>Neither GUID nor link</title>
        <pubDate>Sat, 19 Sep 2026 07:00:00 GMT</pubDate>
      </item>
      <item>
        <guid>https://blog.example.com/posts/untitled</guid>
        <description>An untitled note that is long enough to stand in for its own title when the list needs something to show in the row.</description>
      </item>
      <item>
        <title>Tracked &amp; teased</title>
        <link>https://blog.example.com/posts/tracked?utm_source=rss&amp;id=7&amp;utm_medium=feed</link>
        <guid isPermaLink="false">post-7</guid>
        <description>&lt;p&gt;A teaser that stops short.&amp;#8230; &lt;a href="https://blog.example.com/posts/tracked"&gt;Read More Tracked &amp;amp; teased&lt;/a&gt;&lt;/p&gt;</description>
      </item>
      <item>
        <title>Discussion only</title>
        <link>https://aggregator.example.com/s/abc</link>
        <description>&lt;a href="https://aggregator.example.com/s/abc"&gt;Comments&lt;/a&gt;</description>
      </item>
      <item>
        <title>From the future</title>
        <link>https://blog.example.com/posts/future</link>
        <pubDate>Fri, 01 Jan 2038 00:00:00 GMT</pubDate>
      </item>
    </channel>
    </rss>
    """#.replacingOccurrences(of: "[[BELL]]", with: "\u{07}")
        .replacingOccurrences(of: "[[LONG]]", with: String(repeating: "Long body sentence number one. ", count: 60))

    /// Atom: XHTML content, an HTML summary, a literal "<" in a text title, several links per entry with a relative
    /// one, `published` beside `updated`, fractional seconds.
    static let atom = #"""
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title type="html">Notes &amp;amp; &lt;em&gt;Queries&lt;/em&gt;</title>
      <link rel="self" href="https://notes.example.org/atom.xml"/>
      <link rel="alternate" type="text/html" href="/"/>
      <updated>2026-09-21T10:00:00Z</updated>
      <entry>
        <title>When a &lt; b: comparing things</title>
        <id>tag:notes.example.org,2026:/entries/1</id>
        <link rel="enclosure" href="https://notes.example.org/audio.mp3" type="audio/mpeg"/>
        <link rel="alternate" type="text/html" href="entries/1.html"/>
        <updated>2026-09-21T10:00:00Z</updated>
        <published>2026-09-20T18:45:12.345+02:00</published>
        <summary type="html">&lt;p&gt;A summary with &lt;strong&gt;markup&lt;/strong&gt; and&amp;nbsp;an entity.&lt;/p&gt;</summary>
        <content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><p>XHTML body with <em>real</em> elements &amp; an ampersand.</p><p>Second paragraph<br/>after a break.</p></div></content>
      </entry>
      <entry>
        <title type="text">Updated only</title>
        <id>tag:notes.example.org,2026:/entries/2</id>
        <link href="https://notes.example.org/entries/2.html"/>
        <updated>2026-09-19T06:00:00Z</updated>
        <content type="html">&lt;p&gt;Short.&lt;/p&gt;</content>
      </entry>
    </feed>
    """#

    /// RDF (RSS 1.0): items are siblings of the channel, identified by `rdf:about`, dated by `dc:date`.
    static let rdf = #"""
    <?xml version="1.0"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel rdf:about="https://rdf.example.net/">
        <title>RDF Site</title>
        <link>https://rdf.example.net/</link>
        <items><rdf:Seq><rdf:li rdf:resource="https://rdf.example.net/a"/></rdf:Seq></items>
      </channel>
      <item rdf:about="https://rdf.example.net/a">
        <title>An RDF item</title>
        <link>https://rdf.example.net/a</link>
        <description>Described in RSS 1.0.</description>
        <dc:date>2026-09-18T12:00:00+00:00</dc:date>
      </item>
      <item rdf:about="https://rdf.example.net/b">
        <title>About only</title>
        <dc:date>2026-09-17</dc:date>
      </item>
    </rdf:RDF>
    """#

    /// YouTube: the description lives in `media:group/media:description`; there is no summary or content.
    static let youtube = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
     <link rel="self" href="http://www.youtube.com/feeds/videos.xml?channel_id=UCYO_jab_esuFRV4b17AJtAw"/>
     <id>yt:channel:YO_jab_esuFRV4b17AJtAw</id>
     <title>3Blue1Brown</title>
     <link rel="alternate" href="https://www.youtube.com/channel/UCYO_jab_esuFRV4b17AJtAw"/>
     <entry>
      <id>yt:video:abc123DEF45</id>
      <yt:videoId>abc123DEF45</yt:videoId>
      <title>But what is a Laplace transform?</title>
      <link rel="alternate" href="https://www.youtube.com/watch?v=abc123DEF45"/>
      <author><name>3Blue1Brown</name><uri>https://www.youtube.com/channel/UCYO_jab_esuFRV4b17AJtAw</uri></author>
      <published>2026-09-12T15:00:06+00:00</published>
      <updated>2026-09-14T01:12:44+00:00</updated>
      <media:group>
       <media:title>But what is a Laplace transform?</media:title>
       <media:content url="https://www.youtube.com/v/abc123DEF45?version=3" type="application/x-shockwave-flash" width="640" height="390"/>
       <media:thumbnail url="https://i2.ytimg.com/vi/abc123DEF45/hqdefault.jpg" width="480" height="360"/>
       <media:description>Visualizing the most important tool for differential equations.
    Lessons are funded by viewers: https://3b1b.co/support

    Timestamps: 0:00 - Intro, 2:10 - s-plane</media:description>
       <media:community><media:starRating count="9000" average="5.00" min="1" max="5"/></media:community>
      </media:group>
     </entry>
    </feed>
    """#

    /// A prefix used without ever being declared: fatal to a strict parser, routine in the wild.
    static let undeclaredPrefix = #"""
    <rss version="2.0">
    <channel><title>Sloppy</title><link>https://sloppy.example.com</link>
      <item><title>Undeclared</title><link>https://sloppy.example.com/1</link>
        <content:encoded><![CDATA[<p>Body under a prefix nobody declared.</p>]]></content:encoded>
      </item>
    </channel></rss>
    """#

    /// Cut off mid-entry, as a timed-out download leaves it.
    static let truncated = #"""
    <?xml version="1.0"?>
    <rss version="2.0"><channel><title>Cut short</title>
      <item><title>Complete</title><link>https://cut.example.com/1</link><guid>1</guid></item>
      <item><title>Half an it
    """#

    static let htmlPage = #"""
    <!DOCTYPE html>
    <html><head><title>Example &amp; Sons &mdash; Journal</title>
      <LINK REL='alternate' TYPE='application/rss+xml' TITLE='Example » Comments Feed' HREF='/comments/feed/'>
      <link href="../atom.xml?lang=en&amp;full=1" title="Journal" type="application/atom+xml" rel="alternate home">
      <link rel="stylesheet" href="/style.css">
      <link rel="alternate" type="application/json" href="/feed.json">
    </head><body><p>A page that mentions &lt;rss in passing.</p></body></html>
    """#

    static let bareHTMLPage = "<html><head><title>No feeds advertised</title></head><body>Hello</body></html>"

    static func simpleRSS(title: String, items: Int = 1) -> String {
        let entries = (1...max(1, items)).map { "<item><title>Item \($0)</title><link>https://example.com/\($0)</link><guid>\($0)</guid></item>" }
        return "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>\(title)</title><link>https://example.com/</link>\(entries.joined())</channel></rss>"
    }

    /// Declared as ISO-8859-1 and encoded that way: every accent is a single byte that is invalid UTF-8.
    static var latin1RSS: Data {
        let xml = "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><rss version=\"2.0\"><channel><title>Actualités</title>"
            + "<item><title>Été à Besançon : ça coûte cher ?</title><link>https://fr.example.com/ete</link>"
            + "<description>Le théâtre rouvre à l'automne.</description></item></channel></rss>"
        return xml.data(using: .isoLatin1) ?? Data()
    }

    /// Windows-1252 named only by the HTTP header: curly quotes are bytes 0x91 to 0x94, undefined in Latin-1.
    static var windows1252RSS: Data {
        let xml = "<rss version=\"2.0\"><channel><title>Quotes</title><item><title>“Smart” quotes — it’s fine</title>"
            + "<link>https://cp1252.example.com/1</link></item></channel></rss>"
        return xml.data(using: .windowsCP1252) ?? Data()
    }

    /// UTF-16 with its byte-order mark, as some Windows tools write feeds.
    static var utf16RSS: Data {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><rss version=\"2.0\"><channel><title>Wide</title>"
            + "<item><title>Sixteen bits — naïve café</title><link>https://wide.example.com/1</link></item></channel></rss>"
        return xml.data(using: .utf16) ?? Data()
    }

    static let hackerNews = #"""
    {"hits":[
      {"objectID":"45000001","title":"Show HN: A feed reader that ranks by meaning","url":"https://www.example.dev/beam","created_at_i":1790000000,"points":321,"story_text":null},
      {"objectID":"45000002","title":"Ask HN: How do you read  the web in 2026?","url":null,"created_at_i":1790000600,"story_text":"I&#x27;m curious what people use. <p>RSS still works for me."},
      {"objectID":"45000003","title":null,"url":"https://example.com/untitled","created_at_i":1790001200}
    ],"nbHits":3,"page":0,"hitsPerPage":30}
    """#

    static let arxiv = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title type="html">ArXiv Query: search_query=cat:cs.LG</title>
      <id>http://arxiv.org/api/abc</id>
      <entry>
        <id>http://arxiv.org/abs/2609.01234v2</id>
        <updated>2026-09-20T17:59:59Z</updated>
        <published>2026-09-18T17:00:00Z</published>
        <title>Sparse Attention on
      Unified Memory: A Study</title>
        <summary>  We study sparse attention kernels on unified-memory devices.
    [[ABSTRACT]]
        </summary>
        <author><name>A. Researcher</name></author>
        <link href="http://arxiv.org/abs/2609.01234v2" rel="alternate" type="text/html"/>
        <link title="pdf" href="http://arxiv.org/pdf/2609.01234v2" rel="related" type="application/pdf"/>
      </entry>
    </feed>
    """#.replacingOccurrences(of: "[[ABSTRACT]]", with: String(repeating: "Results hold across model sizes and sequence lengths. ", count: 12))

    static let reddit = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom"><title>Swift</title>
      <link rel="alternate" type="text/html" href="https://www.reddit.com/r/swift/"/>
      <entry>
        <author><name>/u/someone</name></author>
        <content type="html">&lt;!-- SC_OFF --&gt;&lt;div class=&quot;md&quot;&gt;&lt;p&gt;Is structured concurrency worth adopting in an old codebase?&lt;/p&gt; &lt;/div&gt;&lt;!-- SC_ON --&gt; &amp;#32; submitted by &amp;#32; &lt;a href=&quot;https://www.reddit.com/user/someone&quot;&gt; /u/someone &lt;/a&gt; &lt;br/&gt; &lt;span&gt;&lt;a href=&quot;https://www.reddit.com/r/swift/comments/1abc/q/&quot;&gt;[link]&lt;/a&gt;&lt;/span&gt; &amp;#32; &lt;span&gt;&lt;a href=&quot;https://www.reddit.com/r/swift/comments/1abc/q/&quot;&gt;[comments]&lt;/a&gt;&lt;/span&gt;</content>
        <id>t3_1abc</id>
        <link href="https://www.reddit.com/r/swift/comments/1abc/q/"/>
        <updated>2026-09-21T07:00:00+00:00</updated>
        <published>2026-09-21T07:00:00+00:00</published>
        <title>Question about structured concurrency</title>
      </entry>
      <entry>
        <content type="html">&amp;#32; submitted by &amp;#32; &lt;a href=&quot;https://www.reddit.com/user/linker&quot;&gt; /u/linker &lt;/a&gt; &lt;br/&gt; &lt;span&gt;&lt;a href=&quot;https://example.com/post&quot;&gt;[link]&lt;/a&gt;&lt;/span&gt; &amp;#32; &lt;span&gt;&lt;a href=&quot;https://www.reddit.com/r/swift/comments/2def/l/&quot;&gt;[comments]&lt;/a&gt;&lt;/span&gt;</content>
        <id>t3_2def</id>
        <link href="https://www.reddit.com/r/swift/comments/2def/l/"/>
        <published>2026-09-21T06:00:00+00:00</published>
        <title>A link post</title>
      </entry>
    </feed>
    """#

    static let githubReleases = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/" xml:lang="en-US">
      <id>tag:github.com,2008:https://github.com/ml-explore/mlx/releases</id>
      <link type="text/html" rel="alternate" href="https://github.com/ml-explore/mlx/releases"/>
      <link type="application/atom+xml" rel="self" href="https://github.com/ml-explore/mlx/releases.atom"/>
      <title>Release notes from mlx</title>
      <updated>2026-09-15T18:02:11Z</updated>
      <entry>
        <id>tag:github.com,2008:Repository/700000000/v0.30.6</id>
        <updated>2026-09-15T18:02:11Z</updated>
        <link rel="alternate" type="text/html" href="https://github.com/ml-explore/mlx/releases/tag/v0.30.6"/>
        <title>v0.30.6</title>
        <content type="html">&lt;h2&gt;Highlights&lt;/h2&gt;&lt;ul&gt;&lt;li&gt;Faster quantized matmul on M-series GPUs&lt;/li&gt;&lt;li&gt;Fix a crash in &lt;code&gt;mx.compile&lt;/code&gt;&lt;/li&gt;&lt;/ul&gt;</content>
        <author><name>maintainer</name></author>
      </entry>
    </feed>
    """#
}
