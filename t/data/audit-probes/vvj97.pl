my @a = (1,2,3); wantarray(); my @w = (scalar(@a), scalar(reverse("ab", "cd")), scalar(() = (1, 2))); print "@w\n";
