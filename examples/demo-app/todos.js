// Tiny in-memory todo store used to try the orchestrate workflow.
function createStore() {
  const todos = [];
  let nextId = 1;

  return {
    add(title) {
      if (typeof title !== 'string' || title.trim() === '') {
        throw new Error('title is required');
      }
      const todo = { id: nextId++, title: title.trim(), done: false };
      todos.push(todo);
      return todo;
    },
    complete(id) {
      const todo = todos.find((t) => t.id === id);
      if (!todo) throw new Error(`todo ${id} not found`);
      todo.done = true;
      return todo;
    },
    list() {
      return todos.map((t) => ({ ...t }));
    },
  };
}

module.exports = { createStore };
