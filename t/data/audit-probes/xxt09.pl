my $x = "a"; my $c = sub { $x .= "b"; "" }; my $s = $x . $c->() . $x; print "$s\n";
