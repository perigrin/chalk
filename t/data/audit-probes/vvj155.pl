my (%h, @a); @a = (1); $h{x} = [@a]; push @{$h{x}}, 1; print scalar(@a), "\n";
