my $x = 1; sub get { ${$_[0]} } my $r = \$x; $x = 4; print get($r), "\n";
