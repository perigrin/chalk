sub try { my ($c, $h) = @_; my @r = eval { $c->() }; return $h->($@) if $@; @r } print try(sub { 5 }, sub { "h" }), try(sub { die "boom\n" }, sub { "h:$_[0]" });
