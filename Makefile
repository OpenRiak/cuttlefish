# -------------------------------------------------------------------
#
# Copyright (c) 2013-2017 Basho Technologies, Inc.
#
# This file is provided to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file
# except in compliance with the License.  You may obtain
# a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
# -------------------------------------------------------------------

.PHONY	: check clean clean-deps clean-docs clean-dist compile dialyzer \
	  default docs escript test validate veryclean xref

# since we are (principally) a dependency app of riak, we usually are
# built by the top-level rebar3, of a specific version, so let's find
# it in the usual location.
REBAR3 ?= ../riak/rebar3

default : compile

compile :
	$(REBAR3) as prod compile

check :
	$(REBAR3) as check do brt-deps --check, dialyzer, xref

clean :
	$(REBAR3) clean --all

clean-deps : clean
	rm -rf _build

clean-docs :
	$(REBAR3) as docs clean

clean-dist :
	rm -f cuttlefish

docs :
	$(REBAR3) edoc

dialyzer :
	$(REBAR3) as check dialyzer

escript :
	$(REBAR3) as prod escriptize
	cp -a _build/prod/bin/cuttlefish cuttlefish

test :
	$(REBAR3) eunit

validate :
	$(REBAR3) as validate compile

veryclean : clean clean-docs clean-deps clean-dist

xref :
	$(REBAR3) as check xref
