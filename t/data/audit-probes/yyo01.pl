use File::Basename; print basename("/a/b/c.txt"), " ", dirname("/a/b/c.txt"), " ", join("|", fileparse("/a/b/c.txt", qr/\.[^.]*/)), "\n";
