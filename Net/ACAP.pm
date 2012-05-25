#!/usr/local/bin/perl
#
# Copyright (c) 1997-1998 Kevin Johnson <kjj@pobox.com>.
#
# All rights reserved. This program is free software; you can
# redistribute it and/or modify it under the same terms as Perl
# itself.
#
# $Id: ACAP.pm,v 1.1 1998/12/01 02:13:52 ts Exp $

require 5.004;

package Net::ACAP;

use strict;

use IO::Socket;
use Net::xAP qw($xAP_ATOM $xAP_ASTRING $xAP_PARENS);
use Carp;

use vars qw($VERSION @ISA $SEQUENCE);

@ISA = qw(Net::xAP IO::Socket::INET);

my $Debug = 0;

sub new {
  my $class = shift;
  my $type = ref($class) || $class;
  my $host = shift if @_ % 2;
  my %options = @_;

  $options{Debug} ||= $Debug;

  my $self = Net::xAP->new($host, 'acap(674)', Timeout => 10, %options)
    or return undef;

  bless $self, $class;

  $self->{Options} = {%options};

  $self->{Banner} = undef;

  STDERR->autoflush(1);

  $self->_get_banner or return undef;

  return $self;
}

sub _get_banner {
  my $self = shift;

  my $list = $self->getline or return undef;

  $self->debug_print(0, join(' ', @{$list})) if $self->debug;

  return undef unless (($list->[0] eq '*') && ($list->[1] eq 'ACAP'));

  $self->{Banner} = join(' ', @{$list});

  return 1;
}

# hide the password from the debug output.
sub debug_text { $_[2] =~ /^(\d+ login [^\s]+)/i ? "$1 ..." : $_[2] }

###############################################################################
sub banner { return shift->{Banner} }
###############################################################################
# noop
sub noop { $_[0]->command($_[0]->generic_callback, 'noop') }

# logout
sub logout { $_[0]->command($_[0]->logout_callback, 'logout') }

sub logout_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::ACAP::Response->new;
  return sub {
    my $list = shift;
    if (($list->[0] eq '*') && ($list->[1] =~ /^BYE$/i)) {
      # need to claim it, but don't need to do anything with it since we'll
      # be getting a tagged response RSN.
    } elsif ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      $self->connection->close if ($resp->status eq 'OK');
      return $resp;
    } else {
      return 0;
    }
    return 1;
  }
}

# login USER PASSWORD
# gack - going away
sub login {
  $_[0]->command($_[0]->generic_callback,
		 'login', $xAP_ASTRING => $_[1], $xAP_ASTRING => $_[2]);
}

# authenticate ATOM [BASE64TOKEN] @BASE64TOKENS

# search DATASET|CONTEXT @SEARCHMODIFIERS SEARCHCRITERIA

# freecontext CONTEXT

# updatecontext @CONTEXTNAMES

# store @STOREENTRIES

# deletedsince DATASET TIME

# setacl ACLOBJECT ACLIDENTIFIER @ACLRIGHTS

# deleteacl ACLOBJECT [ACLIDENTIFIER]

# myrights ACLOBJECT

# listrights ACLOBJECT

# setquota QUOTAROOT NUMBER|NIL

# getquota DATASET
###############################################################################
sub generic_callback {
  my $self = shift;
  my $seq = $self->next_sequence;
  my $resp = Net::ACAP::Response->new;
  return sub {
    my $list = shift;
    if ($list->[0] =~ /^\d+$/) {
      $resp->parse_status($list);
      return $resp;
    }
    return 0;
  }
}
###############################################################################
package Net::ACAP::Response;

use vars qw(@ISA);
@ISA = qw(Net::xAP::Response);

sub parse_status {
  my $self = shift;
  my $list = shift;
  my @list2 = @{$list};

  $self->{Sequence} = shift(@list2);
  $self->{CmdStatus} = uc(shift(@list2));

  my $str = join(' ', @list2);
  $str =~ /^(?:\(([^\)]+)\) )?(.*)$/;
  $self->{StatusCode} = uc($1 || '');
  $self->{StatusText} = $2;
}
###############################################################################

1;
