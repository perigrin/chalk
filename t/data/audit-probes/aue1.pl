my $f = "/tmp/zz$$"; my $a = -e $f ? 1 : 0; mkdir $f; my $b = -e $f ? 1 : 0; rmdir $f; print "$a$b\n";
