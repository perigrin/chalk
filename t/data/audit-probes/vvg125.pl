use feature 'state'; sub nx { state @s; push @s, $_[0]; scalar @s } nx(1); print nx(2), "\n";
