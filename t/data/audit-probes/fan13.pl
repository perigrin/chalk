my @a=(1,2); my $z=0; eval { for my $x (@a) { $x.="!"; my $q=1/$z; } }; print "@a\n";
