#!/bin/env bash

rm psv2
ln -s psv2_stub psv2

rm ps_search
ln -s ps_search_stub ps_search

rm ps_registration
ln -s ps_registration_stub ps_registration

rm ssa_auth_client
ln -s ssa_auth_client_stub ssa_auth_client

rm ssa_auth_server
ln -s ssa_auth_server_stub ssa_auth_server
