my $x=1; sub rd { $x } sub wr { $x=shift } my $a=rd(); wr(2); my $b=rd(); print "$a$b\n";
