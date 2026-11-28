my $x = 1; my $y = 2; my %r = (a => \$x, b => \$y); ${$r{b}} = 7; print "$x$y\n";
