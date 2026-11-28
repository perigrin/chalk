my $s = "abc"; my $r = \$s; $$r =~ s/b/z/; my $c = sub { $s =~ tr/a/y/ }; $c->(); print "$s\n";
