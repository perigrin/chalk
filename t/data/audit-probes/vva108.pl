our $x = 1; my @s; for (1..2) { local $x = $x + 1; push @s, \$x } print ${$s[0]}, ${$s[1]}, $x, "\n";
