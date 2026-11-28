my %reg; sub on { push @{$reg{$_[0]}}, $_[1] } sub fire { $_->($_[1]) for @{$reg{$_[0]}} } my $log = ""; on(a => sub { $log .= "x$_[0]" }); on(a => sub { $log .= "y" }); fire("a", 1); print "$log\n";
