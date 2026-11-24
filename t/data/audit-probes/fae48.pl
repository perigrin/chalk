my $o={n=>1}; sub d { $_[0]{n}=5; die "a\n" } eval { d($o) }; print $o->{n},"\n";
