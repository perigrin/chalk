my $x = "a"; my $r = \$x; my $s = "$$r$x"; $$r = "b"; $s .= "$$r$x"; print "$s\n";
