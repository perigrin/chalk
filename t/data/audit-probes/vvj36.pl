my @a = (1,2,3); my @d = map { ($_, $_) } @a; my %h = map { $_ => 1 } @a; print scalar(@d), scalar(keys %h), "\n";
