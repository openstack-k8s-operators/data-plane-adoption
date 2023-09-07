Contributing to documentation
=============================

## Rendering documentation locally

Install docs build requirements into virtualenv:

```
python3 -m venv local/docs-venv
source local/docs-venv/bin/activate
pip install -r docs/doc_requirements.txt
```

Serve docs site on localhost:

```
mkdocs serve
```

Click the link it outputs. As you save changes to files modified in your editor,
the browser will automatically show the new content.


## Patterns and tips for contributing to documentation

* Pages concerning individual components/services should make sense in
  the context of the broader adoption procedure. While adopting a
  service in isolation is an option for developers, let's write the
  documentation with the assumption the adoption procedure is being
  done in full, going step by step (one doc after another).

* The procedure should be written with production use in mind. This
  repository could be used as a starting point for product
  technical documentation. We should not tie the documentation to
  something that wouldn't translate well from dev envs to production.

    * This includes not assuming that the source environment is
      Standalone, and the destination is CRC. We can provide examples for
      Standalone/CRC, but it should be possible to use the procedure
      with fuller environments in a way that is obvious from the docs.

* If possible, try to make code snippets copy-pastable. Use shell
  variables if the snippets should be parametrized. Use `oc` rather
  than `kubectl` in snippets.

* Focus on the "happy path" in the docs as much as possible,
  troubleshooting info can go into the Troubleshooting page, or
  alternatively a troubleshooting section at the end of the document,
  visibly separated from the main procedure.

* The full procedure will inevitably happen to be quite long, so let's
  try to be concise in writing to keep the docs consumable (but not to
  a point of making things difficult to understand or omitting
  important things).

* A bash alias can be created for long command however when implementing
  them in the test roles you should transform them to avoid command not
  found errors.
  From:
  ```
  alias openstack="oc exec -t openstackclient -- openstack"

  openstack endpoint list | grep network
  ```
  TO:
  ```
  alias openstack="oc exec -t openstackclient -- openstack"

  ${BASH_ALIASES[openstack]} endpoint list | grep network
  ```