my @q; my $en=sub { push @q,@_ }; my $de=sub { shift @q }; $en->(1,2); my $a=$de->(); $en->(3); print $a, scalar(@q), "@q\n";
