# SeaweedFS buckets and users

This guide matches SeaweedFS chart **4.21.0** and the current Loki, Prometheus,
and Thanos values. It documents manual setup; Git currently deploys SeaweedFS
and its admin login, but does not declare S3 buckets or S3 identities.

## Connect

Applications use this internal S3 endpoint, with region `us-east-1`:

```text
http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333
```

There is no S3 ingress. S3 uses signed access-key/secret-key authentication,
separate from the basic auth on telemetry ingestion ingresses.

To open the Admin UI locally:

```sh
kubectl -n seaweedfs port-forward service/seaweedfs-admin 23646:23646
```

Visit `http://localhost:23646/admin`. Log in as `admin` with the plain value of
`seaweedfs` / `dev` / `/` / `ADMIN_PASSWORD` in Infisical. ESO creates the
`seaweedfs-admin` Kubernetes Secret from it. This login is not an S3 identity.

If your Admin UI exposes bucket/user management, use it to create the resources
below. The shell commands provide a version-specific alternative.

## Required buckets and suggested S3 identities

The bucket names are configured in Git and must match exactly. The identity names
below are suggested; applications authenticate with access keys, not these names.
Use a separate access-key/secret-key pair for each identity.

| Bucket | S3 identity | Consumer | Infisical project and credential keys (`dev`, root path) |
| --- | --- | --- | --- |
| `loki-chunks` | `loki` | Loki chunks, index, and retention/delete-request data | `loki`: `LOKI_S3_ACCESS_KEY_ID`, `LOKI_S3_SECRET_ACCESS_KEY` |
| `prometheus-chunks` | `prometheus` | Prometheus Thanos sidecar block uploads | `prometheus`: `THANOS_S3_ACCESS_KEY_ID`, `THANOS_S3_SECRET_ACCESS_KEY` |
| `thanos-chunks` | `thanos` | Receive uploads, Store Gateway reads, Compactor reads/writes/deletes | `thanos`: `S3_ACCESS_KEY`, `S3_SECRET_KEY` |

For a simple local setup, give each identity **Read, Write, List, Tagging** actions
scoped to its own bucket. `Write` includes object deletion, needed by retention
and compaction. Do not grant unrestricted `Admin` access to application users.
Create buckets as an operator rather than granting applications global bucket
creation permissions.

Prometheus's sidecar and Thanos Receive currently write to **different buckets**.
The deployed Thanos Store Gateway reads only `thanos-chunks`; creating
`prometheus-chunks` does not make those historical blocks queryable through it.
A separate Store Gateway or deliberate storage configuration change is needed
if those sidecar blocks must also appear in the Thanos datasource.

## Create through the SeaweedFS shell

Open a shell using an existing master pod:

```sh
kubectl -n seaweedfs exec -it seaweedfs-master-0 -- \
  weed shell \
  -master=seaweedfs-master.seaweedfs.svc.cluster.local:9333 \
  -filer=seaweedfs-filer-client.seaweedfs.svc.cluster.local:8888
```

The commands below are entered **inside `weed shell`**, not your host shell.
Replace every placeholder with the real credential pair. Treat the session's
output as sensitive: `s3.configure` can print credentials.

```text
s3.configure -user=loki -actions=Read,Write,List,Tagging -buckets=loki-chunks -access_key=<loki-access-key> -secret_key=<loki-secret-key> -apply
s3.configure -user=prometheus -actions=Read,Write,List,Tagging -buckets=prometheus-chunks -access_key=<prometheus-access-key> -secret_key=<prometheus-secret-key> -apply
s3.configure -user=thanos -actions=Read,Write,List,Tagging -buckets=thanos-chunks -access_key=<thanos-access-key> -secret_key=<thanos-secret-key> -apply

s3.bucket.create -name=loki-chunks -owner=loki
s3.bucket.create -name=prometheus-chunks -owner=prometheus
s3.bucket.create -name=thanos-chunks -owner=thanos
```

Skip bucket creation for buckets that already exist; preserve existing data and
identities. Set the matching bucket owner when creating through the UI too.
The shell's `-owner` value is the S3 identity name, not its access key.
Do not enable Object Lock for these telemetry buckets: retention and compaction
need to delete objects.

Copy each exact credential pair into the Infisical keys in the table. Infisical
values contain only the key itself, without quotes, JSON, or `username:` prefixes.

Creating identities changes S3 authentication behavior. Configure every application
pair and remove any unintended anonymous/global grants before relying on access
restrictions. The chart does not currently supply a static S3 identity config;
the shell persists its changes through the filer's IAM configuration.

## Verify

Wait for the application ExternalSecrets to sync:

```sh
kubectl get externalsecrets -n loki
kubectl get externalsecrets -n prometheus
kubectl get externalsecrets -n thanos
```

If you changed credentials after pods started, restart the consumers so their
environment variables reload. Relevant workloads are Loki's single-binary
StatefulSet, the Prometheus server Deployment (including its sidecar), and
Thanos Receive, Store Gateway, and Compactor StatefulSets. Confirm names with
`kubectl get deployment,statefulset -n <namespace>` before restarting.

Check application logs for S3 access errors and inspect the buckets for objects.
Recent metrics can be queried directly from Receive before any S3 block exists.
Thanos normally uploads completed two-hour TSDB blocks, so an initially empty
bucket does not by itself mean authentication failed.

For an explicit S3 check, port-forward the gateway in one terminal:

```sh
kubectl -n seaweedfs port-forward service/seaweedfs-s3 8333:8333
```

In another terminal, configure your AWS CLI session with one application's
`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, then test its bucket (example:
Thanos credentials):

```sh
aws --endpoint-url http://localhost:8333 --region us-east-1 \
  s3 ls s3://thanos-chunks/
```

An empty successful listing is valid for a new bucket. Also test that a different
application's bucket is denied; successful own-bucket access alone does not prove
isolation. Avoid listing all buckets as the test, since scoped users may not have
that permission.

## References

- [SeaweedFS 4.21 S3 user configuration command](https://github.com/seaweedfs/seaweedfs/blob/4.21/weed/shell/command_s3_configure.go)
- [SeaweedFS 4.21 bucket creation and ownership](https://github.com/seaweedfs/seaweedfs/blob/4.21/weed/shell/command_s3_bucket_create.go)
- [Infisical setup and secret inventory](infisical-setup.md)
- [SeaweedFS values](../charts/seaweedfs/values.yaml)
- [Loki values](../charts/loki/values.yaml)
- [Prometheus values](../charts/prometheus/values.yaml)
- [Thanos values](../charts/thanos/values.yaml)
