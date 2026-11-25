my %h=(a=>1,b=>2); my ($k)=sort keys %h; my @v=@h{sort keys %h}; my %inv=map { $h{$_} => $_ } keys %h; while (my ($kk,$vv)=each %inv) { } print "$k@v$inv{1}$inv{2}\n";
