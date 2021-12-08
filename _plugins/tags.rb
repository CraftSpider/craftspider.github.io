
module Tags
    class Generator < Jekyll::Generator
        safe true

        def generate(site)
            tags = []
            for post in site.posts.docs do
                tags.push(*post.data["tags"])
            end

            for tag in tags do
                site.pages << TagPage.new(site, tag)
            end
        end
    end

    class TagPage < Jekyll::Page
        def initialize(site, tag)
            @site = site
            @base = site.source
            @dir = 'tag'

            @basename  = tag
            @ext = '.html'
            @name = tag + '.html'

            @data = {
                'tag' => tag
            }

            data.default_proc = proc do |_, key|
                if key == "layout" then
                    "tag_index"
                else
                    site.frontmatter_defaults.find(relative_path, :categories, key)
                end
            end
        end
    end

end

