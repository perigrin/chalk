my %h=(k=>1); my $f=sub { $h{k}=9; 0 }; my @l = ($h{k}, $f->(), $h{k}); print "@l\n";
