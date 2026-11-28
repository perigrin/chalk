sub sw { my $t = $_[0]; $_[0] = $_[1]; $_[1] = $t } my @a = (1, 2); sw(@a); sw($a[0], $a[0]); print "@a\n";
