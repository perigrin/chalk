my @a=(1,2,3); my @b = map { $_ => 1 } @a; my %h = map { $_ => $_ * 2 } @a; print scalar(@b), join(",", map {$h{$_}} sort keys %h), "\n";
