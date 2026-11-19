our $g = 1; my $a = $main::g; $g = 2; { no strict "refs"; my $n = "g"; my $b = ${"main::$n"}; print "$a$b\n"; }
