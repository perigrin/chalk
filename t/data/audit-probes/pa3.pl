our @g = (4, 5); my $n = @g + 1; print "two\n" if @g == 2; pop @g; pop @g; print "empty\n" unless @g; print !@g ? "e" : "ne", " $n\n";
