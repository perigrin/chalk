my $x=1; my $f = sub { $x=9; my ($p)=@_; $p }; print $f->($x), "$x\n";
