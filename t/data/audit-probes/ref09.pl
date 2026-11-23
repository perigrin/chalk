my %h; my $set=sub { $h{$_[0]}=$_[1] }; $set->("a",1); my $n=keys %h; $set->("b",2); print "$n ".scalar(keys %h)."\n";
