my $x; eval { $x = undef; my $v = $$x; }; print $@ ? "err" : "ok", "\n";
