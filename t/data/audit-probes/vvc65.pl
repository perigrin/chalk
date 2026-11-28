our @a = (1,2,3); sub sum { my $t = 0; $t += $_ for @b; $t } *b = \@a; our @b; print sum(), "\n";
