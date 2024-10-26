const {
  postgresuser,
  postgreshost,
  postgresdatabase,
  postgrespassword,
  postgresport
} = require('./secrets.js');


const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const { Pool } = require('pg');

// Set up the Express app
const app = express();
app.use(bodyParser.json());
app.use(cors());

// PostgreSQL connection pool
const pool = new Pool({
  user: postgresuser,
  host: postgreshost,
  database: postgresdatabase,
  password: postgrespassword,
  port: postgresport,
});

// Get events for a specific user
app.get('/events/:userId', async (req, res) => {
  const userId = req.params.userId;
  const result = await pool.query('SELECT * FROM events WHERE user_id = $1', [userId]);
  res.json(result.rows);
});

// Add a new event
app.post('/events', async (req, res) => {
  const { title, event_time, color, user_id } = req.body;
  const result = await pool.query(
    'INSERT INTO events (title, event_time, color, user_id) VALUES ($1, $2, $3, $4) RETURNING *',
    [title, event_time, color, user_id]
  );
  res.json(result.rows[0]);
});

// Edit an event
app.put('/events/:id', async (req, res) => {
  const id = req.params.id;
  const { title, event_time, color } = req.body;
  const result = await pool.query(
    'UPDATE events SET title = $1, event_time = $2, color = $3 WHERE id = $4 RETURNING *',
    [title, event_time, color, id]
  );
  res.json(result.rows[0]);
});

// Delete an event
app.delete('/events/:id', async (req, res) => {
  const id = req.params.id;
  await pool.query('DELETE FROM events WHERE id = $1', [id]);
  res.json({ message: 'Event deleted' });
});

// Start the server
const port = 3000;
app.listen(port, () => {
  console.log(`Server is running on port ${port}`);
});
