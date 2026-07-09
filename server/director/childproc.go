package director

import (
	"fmt"
	"os"
	"os/exec"
)

// execChild is a real child process implementing Child.
type execChild struct {
	port int
	code string
	cmd  *exec.Cmd
	done chan struct{}
}

func (c *execChild) Port() int             { return c.port }
func (c *execChild) Code() string          { return c.code }
func (c *execChild) Done() <-chan struct{} { return c.done }

func (c *execChild) Kill() {
	if c.cmd.Process != nil {
		_ = c.cmd.Process.Kill()
	}
}

// startProcess launches an already-built command and wires its Done channel to
// the process exit. Split out from the Godot specifics so it can be tested with
// a harmless process (e.g. sleep).
func startProcess(cmd *exec.Cmd, port int, code string) (*execChild, error) {
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	ch := &execChild{port: port, code: code, cmd: cmd, done: make(chan struct{})}
	go func() {
		_ = cmd.Wait()
		close(ch.done)
	}()
	return ch, nil
}

// SpawnGodot returns a SpawnFunc that launches a headless single-match Godot
// server bound to the given internal port and seeded with the room code. Child
// stdout/stderr are forwarded so matches show up in the Railway logs.
func SpawnGodot(godotBin, projectPath string) SpawnFunc {
	return func(port int, code string) (Child, error) {
		cmd := exec.Command(
			godotBin, "--headless", "--path", projectPath, "--",
			"--server",
			fmt.Sprintf("--port=%d", port),
			"--room="+code,
		)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		return startProcess(cmd, port, code)
	}
}
