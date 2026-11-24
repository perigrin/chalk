my %h; my $set=sub { $h{$_[0]}=$_[1] }; $set->(a=>1); my %c=%h; $set->(b=>2); print scalar(keys %c), scalar(keys %h), "\n";
