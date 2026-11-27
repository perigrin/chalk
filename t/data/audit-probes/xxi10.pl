our $g = 1; my $n = "g"; my $v; { no strict 'refs'; $v = ${"main::$n"}; ${"main::$n"}++; } print "$v$g\n";
